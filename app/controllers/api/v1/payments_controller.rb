module Api
  module V1
    class PaymentsController < ApplicationController
      skip_before_action :verify_authenticity_token

      CONTRIBUTION_TYPES = %w[donation offering tithe other].freeze

      # POST /api/v1/payment
      def create
        input = extract_payment_input
        error = validate_payment_input(input)
        return render json: { error: error }, status: :unprocessable_entity if error

        token = generate_mpesa_token
        return render_unavailable if token.blank?

        handle_stk_push_result(input, *send_stk_push(token, input[:phone], input[:amount], input[:contribution_type]))
      rescue StandardError => e
        Rails.logger.error("M-PESA STK Push Error: #{e.message}")
        render json: { error: 'An unexpected error occurred. Please try again.' }, status: :internal_server_error
      end

      # GET /api/v1/payment/verify?code=SGL4X7K2PQ
      def verify
        code = params[:code].to_s.strip.upcase
        payment = Payment.find_by(transaction_id: code) if code.match?(/\A[A-Z0-9]{8,12}\z/)
        return render json: { status: 'not_found' }, status: :ok unless payment

        render json: { status: payment.status, amount: payment.amount, contribution_type: payment.contribution_type }
      rescue StandardError => e
        Rails.logger.error("M-PESA Verify Error: #{e.message}")
        render json: { error: 'Could not check that code right now. Please try again.' }, status: :internal_server_error
      end

      # GET /api/v1/payment/status?checkout_request_id=ws_CO_...
      def status
        checkout_id = params[:checkout_request_id].to_s.strip
        return render json: { error: 'Missing checkout_request_id' }, status: :bad_request if checkout_id.blank?

        payment = Payment.find_by(checkout_request_id: checkout_id)
        return render json: { error: 'Payment not found' }, status: :not_found unless payment

        if payment.status == 'pending'
          query_mpesa_status(payment)
          payment.reload
        end
        render json: payment.slice(:status, :amount, :contribution_type, :transaction_id, :note, :result_description)
      rescue StandardError => e
        Rails.logger.error("M-PESA Status Query Error: #{e.message}")
        render json: { status: payment&.status || 'pending', error: 'Could not refresh status right now' }, status: :ok
      end

      # POST /api/v1/callback
      def callback
        payload = parse_callback_payload
        Rails.logger.info("M-PESA Callback received: #{payload.inspect}")

        stk_callback = payload.dig('Body', 'stkCallback') || {}
        checkout_id = stk_callback['CheckoutRequestID'].to_s.strip
        payment = Payment.find_by(checkout_request_id: checkout_id)

        if payment
          apply_callback_result(payment, stk_callback)
        else
          Rails.logger.warn("M-PESA callback for unknown CheckoutRequestID: #{checkout_id.inspect}")
        end
        render json: { ResultCode: 0, ResultDesc: 'Accepted' }, status: :ok
      rescue StandardError => e
        Rails.logger.error("M-PESA Callback Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { ResultCode: 0, ResultDesc: 'Accepted' }, status: :ok
      end

      private

      def extract_payment_input
        digits = params[:phone].to_s.gsub(/\D/, '').sub(/\A0/, '254')
        { phone: digits.match?(/\A[17]\d{8}\z/) ? "254#{digits}" : digits, amount: params[:amount].to_i,
          contribution_type: params[:contribution_type].to_s.downcase,
          note: params[:note].to_s.strip.first(200).presence }
      end

      def validate_payment_input(input)
        unless input[:phone].match?(/\A254[17]\d{8}\z/)
          return 'Invalid phone number. Use the format 07XXXXXXXX or 2547XXXXXXXX.'
        end
        return 'Amount must be at least KES 1.' if input[:amount] < 1
        unless CONTRIBUTION_TYPES.include?(input[:contribution_type])
          return "Contribution type must be one of: #{CONTRIBUTION_TYPES.join(', ')}."
        end

        'Please tell us what this contribution is for.' if input[:contribution_type] == 'other' && input[:note].blank?
      end

      def render_unavailable
        Rails.logger.error('M-PESA STK Push Error: could not obtain access token')
        msg = 'Payment service is unavailable right now. Please try again shortly.'
        render json: { error: msg }, status: :bad_gateway
      end

      def send_stk_push(token, phone, amount, contribution_type)
        shortcode, timestamp, password = mpesa_credentials
        ref = contribution_type.capitalize
        payload = { 'BusinessShortCode' => shortcode, 'Password' => password, 'Timestamp' => timestamp,
                    'TransactionType' => 'CustomerPayBillOnline', 'Amount' => amount, 'PartyA' => phone,
                    'PartyB' => shortcode, 'PhoneNumber' => phone, 'CallBackURL' => ENV.fetch('CALLBACK_URL', nil),
                    'AccountReference' => "AIC-#{ref}", 'TransactionDesc' => "#{ref} contribution to AIC Kabuku" }
        res = mpesa_post('/mpesa/stkpush/v1/processrequest', token, payload)
        [parse_json_safe(res.body), res.code]
      end

      def handle_stk_push_result(input, body, code)
        if code == 200 && body['ResponseCode'] == '0'
          Payment.create!(phone_number: input[:phone], amount: input[:amount], note: input[:note],
                          contribution_type: input[:contribution_type], merchant_request_id: body['MerchantRequestID'],
                          checkout_request_id: body['CheckoutRequestID'], status: 'pending')
          msg = 'Payment request sent! Please check your phone and enter your M-PESA PIN.'
          render json: { message: msg, checkout_request_id: body['CheckoutRequestID'] }, status: :ok
        else
          msg = body['errorMessage'] || body['ResponseDescription'] || 'Failed to initiate payment'
          render json: { error: msg }, status: :unprocessable_entity
        end
      end

      def parse_callback_payload
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        params.to_unsafe_h.deep_stringify_keys
      end

      def apply_callback_result(payment, stk_callback)
        if stk_callback['ResultCode'].to_i.zero?
          items = (stk_callback.dig('CallbackMetadata', 'Item') || []).to_h { |i| [i['Name'], i['Value']] }
          payment.update!(status: 'success', transaction_id: items['MpesaReceiptNumber'],
                          amount: items['Amount'] || payment.amount, result_description: stk_callback['ResultDesc'])
        else
          payment.update!(status: 'failed', result_description: stk_callback['ResultDesc'])
        end
      end

      def generate_mpesa_token
        raw = "#{ENV.fetch('MPESA_CONSUMER_KEY', nil)}:#{ENV.fetch('MPESA_CONSUMER_SECRET', nil)}"
        url = "#{ENV.fetch('MPESA_BASE_URL', nil)}/oauth/v1/generate?grant_type=client_credentials"
        res = HTTParty.get(url, headers: { 'Authorization' => "Basic #{Base64.strict_encode64(raw)}" })
        parse_json_safe(res.body)['access_token']
      end

      def query_mpesa_status(payment)
        token = generate_mpesa_token
        return if token.blank?

        shortcode, timestamp, password = mpesa_credentials
        payload = { 'BusinessShortCode' => shortcode, 'Password' => password,
                    'Timestamp' => timestamp, 'CheckoutRequestID' => payment.checkout_request_id }
        res = mpesa_post('/mpesa/stkpushquery/v1/query', token, payload, timeout: 8)
        apply_stk_query_result(payment, parse_json_safe(res.body))
      rescue StandardError => e
        Rails.logger.warn("STK Query query_mpesa_status error: #{e.message}")
      end

      def apply_stk_query_result(payment, body)
        code = body['ResultCode'].to_s
        if code == '0'
          payment.update!(status: 'success', result_description: body['ResultDesc'] || 'Payment processed successfully')
        elsif %w[1032 1037 2001 1].include?(code)
          desc = body['ResultDesc'] || 'Transaction not completed'
          payment.update!(status: code == '1032' ? 'cancelled' : 'failed', result_description: desc)
        end
      end

      def mpesa_credentials
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        shortcode = ENV.fetch('MPESA_PAYBILL_SHORTCODE', '').strip.split.first
        [shortcode, timestamp, Base64.strict_encode64("#{shortcode}#{ENV.fetch('MPESA_PASSKEY', nil)}#{timestamp}")]
      end

      def mpesa_post(path, token, payload, **)
        headers = { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
        HTTParty.post("#{ENV.fetch('MPESA_BASE_URL', nil)}#{path}", body: payload.to_json, headers: headers, **)
      end

      def parse_json_safe(raw)
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
