module Api
  module V1
    class PaymentsController < ApplicationController
      # Skips CSRF token verification for requests to this controller
      skip_before_action :verify_authenticity_token

      # POST /api/v1/payment
      def create
        phone = params[:phone]
        amount = params[:amount] || 100 # Default amount if not provided

        # Validate the phone number format
        unless valid_phone_number?(phone)
          return render json: { error: 'Invalid phone number format' }, status: :unprocessable_entity
        end

        # Generate OAuth token
        token = generate_mpesa_token

        # Prepare the STK Push request
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        shortcode = ENV.fetch('MPESA_PAYBILL_SHORTCODE', nil)
        password = Base64.strict_encode64("#{shortcode}#{ENV.fetch('MPESA_PASSKEY', nil)}#{timestamp}")

        stk_push_data = {
          'BusinessShortCode' => shortcode,
          'Password' => password,
          'Timestamp' => timestamp,
          'TransactionType' => 'CustomerPayBillOnline',
          'Amount' => amount,
          'PartyA' => phone,
          'PartyB' => shortcode,
          'PhoneNumber' => phone,
          'CallBackURL' => ENV.fetch('CALLBACK_URL', nil),
          'AccountReference' => 'Payment for goods',
          'TransactionDesc' => 'Payment request for services'
        }

        # Send the STK Push request
        response = HTTParty.post("#{ENV.fetch('MPESA_BASE_URL', nil)}/mpesa/stkpush/v1/processrequest",
                                 body: stk_push_data.to_json,
                                 headers: {
                                   'Authorization' => "Bearer #{token}",
                                   'Content-Type' => 'application/json'
                                 })

        if response.code == 200
          render json: { message: 'Payment request sent. Please check your phone.' }, status: :ok
        else
          render json: { error: 'Failed to initiate payment' }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/callback
      def callback
        callback_data = params[:Body][:stkCallback]

        if callback_data[:ResultCode] == 0 # rubocop:disable Style/NumericPredicate -- .zero? would raise on nil
          # Handle successful payment
          transaction_id = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == 'MpesaReceiptNumber' }[:Value]
          amount = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == 'Amount' }[:Value]
          phone_number = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == 'PhoneNumber' }[:Value]

          # Log payment details (Assuming you have a Payment model)
          Payment.create(
            phone_number: phone_number,
            amount: amount,
            transaction_id: transaction_id,
            status: 'success'
          )

          render json: { message: 'Payment successful', transaction_id: transaction_id }, status: :ok
        else
          # Handle failed payment
          render json: { message: 'Payment failed' }, status: :unprocessable_entity
        end
      end

      private

      def generate_mpesa_token
        consumer_key = ENV.fetch('MPESA_CONSUMER_KEY', nil)
        consumer_secret = ENV.fetch('MPESA_CONSUMER_SECRET', nil)
        credentials = Base64.strict_encode64("#{consumer_key}:#{consumer_secret}")

        response = HTTParty.get("#{ENV.fetch('MPESA_BASE_URL', nil)}/oauth/v1/generate?grant_type=client_credentials",
                                headers: {
                                  'Authorization' => "Basic #{credentials}"
                                })

        JSON.parse(response.body)['access_token']
      end

      def valid_phone_number?(phone)
        phone.match?(/^2547\d{8}$/) # Example: Validates Kenyan phone numbers
      end
    end
  end
end
