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
        password = Base64.strict_encode64("#{ENV['MPESA_PAYBILL_SHORTCODE']}#{ENV['MPESA_PASSKEY']}#{timestamp}")

        stk_push_data = {
          "BusinessShortCode" => ENV['MPESA_PAYBILL_SHORTCODE'],
          "Password" => password,
          "Timestamp" => timestamp,
          "TransactionType" => "CustomerPayBillOnline",
          "Amount" => amount,
          "PartyA" => phone,
          "PartyB" => ENV['MPESA_PAYBILL_SHORTCODE'],
          "PhoneNumber" => phone,
          "CallBackURL" => ENV['CALLBACK_URL'],
          "AccountReference" => "Payment for goods",
          "TransactionDesc" => "Payment request for services"
        }

        # Send the STK Push request
        response = HTTParty.post("#{ENV['MPESA_BASE_URL']}/mpesa/stkpush/v1/processrequest",
          body: stk_push_data.to_json,
          headers: {
            "Authorization" => "Bearer #{token}",
            "Content-Type" => "application/json"
          }
        )

        if response.code == 200
          render json: { message: 'Payment request sent. Please check your phone.' }, status: :ok
        else
          render json: { error: 'Failed to initiate payment' }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/callback
      def callback
        callback_data = params[:Body][:stkCallback]

        if callback_data[:ResultCode] == 0
          # Handle successful payment
          transaction_id = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == "MpesaReceiptNumber" }[:Value]
          amount = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == "Amount" }[:Value]
          phone_number = callback_data[:CallbackMetadata][:Item].find { |i| i[:Name] == "PhoneNumber" }[:Value]

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
        consumer_key = ENV['MPESA_CONSUMER_KEY']
        consumer_secret = ENV['MPESA_CONSUMER_SECRET']
        credentials = Base64.strict_encode64("#{consumer_key}:#{consumer_secret}")

        response = HTTParty.get("#{ENV['MPESA_BASE_URL']}/oauth/v1/generate?grant_type=client_credentials",
          headers: {
            "Authorization" => "Basic #{credentials}"
          }
        )

        JSON.parse(response.body)['access_token']
      end

      def valid_phone_number?(phone)
        phone.match?(/^2547\d{8}$/) # Example: Validates Kenyan phone numbers
      end
    end
  end
end
