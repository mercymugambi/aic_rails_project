module Api
  module V1
    class PaymentsController < ApplicationController
      # M-PESA callbacks and STK push are public (no login, no CSRF)
      skip_before_action :verify_authenticity_token

      CONTRIBUTION_TYPES = %w[donation offering tithe other].freeze

      # POST /api/v1/payment
      #
      # Accepts: { phone, amount, contribution_type, note? }
      # Initiates an M-PESA STK push and persists a pending Payment row.
      def create
        phone = sanitize_phone(params[:phone])
        amount = params[:amount].to_i
        contribution_type = params[:contribution_type].to_s.downcase
        note = params[:note].to_s.strip.first(200).presence

        # ── Validations ──────────────────────────────────────────────
        unless valid_phone_number?(phone)
          return render json: { error: 'Invalid phone number. Use the format 07XXXXXXXX or 2547XXXXXXXX.' }, status: :unprocessable_entity
        end

        if amount < 1
          return render json: { error: 'Amount must be at least KES 1.' }, status: :unprocessable_entity
        end

        unless CONTRIBUTION_TYPES.include?(contribution_type)
          return render json: { error: "Contribution type must be one of: #{CONTRIBUTION_TYPES.join(', ')}." }, status: :unprocessable_entity
        end

        if contribution_type == 'other' && note.blank?
          return render json: { error: 'Please tell us what this contribution is for.' }, status: :unprocessable_entity
        end

        # ── OAuth token ───────────────────────────────────────────────
        token = generate_mpesa_token
        if token.blank?
          Rails.logger.error('M-PESA STK Push Error: could not obtain access token')
          return render json: { error: 'Payment service is unavailable right now. Please try again shortly.' }, status: :bad_gateway
        end

        # ── STK Push ──────────────────────────────────────────────────
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        shortcode = ENV.fetch('MPESA_PAYBILL_SHORTCODE', '').strip.split.first
        password  = Base64.strict_encode64("#{shortcode}#{ENV.fetch('MPESA_PASSKEY', nil)}#{timestamp}")

        account_ref = contribution_type.capitalize
        stk_push_data = {
          'BusinessShortCode' => shortcode,
          'Password'          => password,
          'Timestamp'         => timestamp,
          'TransactionType'   => 'CustomerPayBillOnline',
          'Amount'            => amount,
          'PartyA'            => phone,
          'PartyB'            => shortcode,
          'PhoneNumber'       => phone,
          'CallBackURL'       => ENV.fetch('CALLBACK_URL', nil),
          'AccountReference'  => "AIC-#{account_ref}",
          'TransactionDesc'   => "#{account_ref} contribution to AIC Kabuku"
        }

        response = HTTParty.post(
          "#{ENV.fetch('MPESA_BASE_URL', nil)}/mpesa/stkpush/v1/processrequest",
          body: stk_push_data.to_json,
          headers: {
            'Authorization' => "Bearer #{token}",
            'Content-Type'  => 'application/json'
          }
        )

        body = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

        if response.code == 200 && body['ResponseCode'] == '0'
          # Persist a pending record so the callback can match it later.
          Payment.create!(
            phone_number:         phone,
            amount:               amount,
            contribution_type:    contribution_type,
            note:                 note,
            merchant_request_id:  body['MerchantRequestID'],
            checkout_request_id:  body['CheckoutRequestID'],
            status:               'pending'
          )

          render json: {
            message:  'Payment request sent! Please check your phone and enter your M-PESA PIN.',
            checkout_request_id: body['CheckoutRequestID']
          }, status: :ok
        else
          error_msg = body['errorMessage'] || body['ResponseDescription'] || 'Failed to initiate payment'
          render json: { error: error_msg }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("M-PESA STK Push Error: #{e.message}")
        render json: { error: 'An unexpected error occurred. Please try again.' }, status: :internal_server_error
      end

      # GET /api/v1/payment/verify?code=SGL4X7K2PQ
      #
      # Lets a giver confirm a payment by its M-PESA receipt code.
      # Always answers 200 with a status: success | pending | failed | not_found.
      # Only non-sensitive fields are returned (no phone number).
      def verify
        code = params[:code].to_s.strip.upcase

        unless code.match?(/\A[A-Z0-9]{8,12}\z/)
          return render json: { status: 'not_found' }, status: :ok
        end

        payment = Payment.find_by(transaction_id: code)
        return render json: { status: 'not_found' }, status: :ok unless payment

        render json: {
          status:            payment.status,
          amount:            payment.amount,
          contribution_type: payment.contribution_type
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("M-PESA Verify Error: #{e.message}")
        render json: { error: 'Could not check that code right now. Please try again.' }, status: :internal_server_error
      end

      # GET /api/v1/payment/status?checkout_request_id=ws_CO_...
      #
      # Checks the status of a pending payment.
      # If still pending, queries Safaricom's STK push query endpoint to get the latest status.
      def status
        checkout_id = params[:checkout_request_id].to_s.strip
        return render json: { error: 'Missing checkout_request_id' }, status: :bad_request if checkout_id.blank?

        payment = Payment.find_by(checkout_request_id: checkout_id)
        return render json: { error: 'Payment not found' }, status: :not_found unless payment

        # If still pending, query Safaricom STK Push Query API
        if payment.status == 'pending'
          query_mpesa_status(payment)
          payment.reload
        end

        render json: {
          status:             payment.status,
          amount:             payment.amount,
          contribution_type:  payment.contribution_type,
          transaction_id:     payment.transaction_id,
          note:               payment.note,
          result_description: payment.result_description
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("M-PESA Status Query Error: #{e.message}")
        render json: {
          status: payment&.status || 'pending',
          error: 'Could not refresh status right now'
        }, status: :ok
      end

      # POST /api/v1/callback
      #
      # Safaricom delivers the STK result here (raw JSON body). We deep-stringify
      # all keys before digging so that symbol vs. string mismatches never silently
      # cause a lookup miss.
      def callback
        # Rails wraps JSON params under the root key, but Safaricom sends the
        # payload at the top level, so we work directly with `request.body`.
        raw_body = request.body.read
        payload  = begin
          JSON.parse(raw_body)
        rescue JSON::ParserError
          # Fallback: use whatever Rails already parsed (e.g. in tests)
          params.to_unsafe_h.deep_stringify_keys
        end

        Rails.logger.info("M-PESA Callback received: #{payload.inspect}")

        stk_callback = payload.dig('Body', 'stkCallback') || {}
        checkout_id  = stk_callback['CheckoutRequestID'].to_s.strip
        result_code  = stk_callback['ResultCode']

        payment = Payment.find_by(checkout_request_id: checkout_id)

        unless payment
          Rails.logger.warn("M-PESA callback for unknown CheckoutRequestID: #{checkout_id.inspect}")
          return render json: { ResultCode: 0, ResultDesc: 'Accepted' }, status: :ok
        end

        if result_code.to_i.zero?
          # Extract metadata items
          items   = stk_callback.dig('CallbackMetadata', 'Item') || []
          receipt = items.find { |i| i['Name'] == 'MpesaReceiptNumber' }&.dig('Value')
          paid    = items.find { |i| i['Name'] == 'Amount' }&.dig('Value')

          payment.update!(
            status:             'success',
            transaction_id:     receipt,
            amount:             paid || payment.amount,
            result_description: stk_callback['ResultDesc']
          )
        else
          payment.update!(
            status:             'failed',
            result_description: stk_callback['ResultDesc']
          )
        end

        # Safaricom expects a 200 success response regardless of our outcome
        render json: { ResultCode: 0, ResultDesc: 'Accepted' }, status: :ok
      rescue StandardError => e
        Rails.logger.error("M-PESA Callback Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { ResultCode: 0, ResultDesc: 'Accepted' }, status: :ok
      end

      private

      def generate_mpesa_token
        consumer_key    = ENV.fetch('MPESA_CONSUMER_KEY', nil)
        consumer_secret = ENV.fetch('MPESA_CONSUMER_SECRET', nil)
        credentials     = Base64.strict_encode64("#{consumer_key}:#{consumer_secret}")

        response = HTTParty.get(
          "#{ENV.fetch('MPESA_BASE_URL', nil)}/oauth/v1/generate?grant_type=client_credentials",
          headers: { 'Authorization' => "Basic #{credentials}" }
        )

        JSON.parse(response.body)['access_token']
      rescue JSON::ParserError
        nil
      end

      def query_mpesa_status(payment)
        token = generate_mpesa_token
        return unless token.present?

        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        shortcode = ENV.fetch('MPESA_PAYBILL_SHORTCODE', '').strip.split.first
        password  = Base64.strict_encode64("#{shortcode}#{ENV.fetch('MPESA_PASSKEY', nil)}#{timestamp}")

        response = HTTParty.post(
          "#{ENV.fetch('MPESA_BASE_URL', nil)}/mpesa/stkpushquery/v1/query",
          body: {
            'BusinessShortCode' => shortcode,
            'Password'          => password,
            'Timestamp'         => timestamp,
            'CheckoutRequestID' => payment.checkout_request_id
          }.to_json,
          headers: {
            'Authorization' => "Bearer #{token}",
            'Content-Type'  => 'application/json'
          },
          timeout: 8
        )

        body = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

        result_code = body['ResultCode'].to_s

        if result_code == '0'
          payment.update!(
            status:             'success',
            result_description: body['ResultDesc'] || 'Payment processed successfully'
          )
        elsif %w[1032 1037 2001 1].include?(result_code)
          new_status = (result_code == '1032' ? 'cancelled' : 'failed')
          payment.update!(
            status:             new_status,
            result_description: body['ResultDesc'] || 'Transaction not completed'
          )
        end
      rescue StandardError => e
        Rails.logger.warn("STK Query query_mpesa_status error: #{e.message}")
      end

      # Normalise common Kenyan phone inputs → 254XXXXXXXXX
      #   0712345678 / 712345678 / +254712345678 / 254712345678
      def sanitize_phone(raw)
        digits = raw.to_s.gsub(/\D/, '')
        digits = "254#{digits[1..]}" if digits.start_with?('0')
        digits = "254#{digits}" if digits.match?(/\A[17]\d{8}\z/)
        digits
      end

      # Safaricom numbers start 2547… or 2541…
      def valid_phone_number?(phone)
        phone.match?(/\A254[17]\d{8}\z/)
      end
    end
  end
end