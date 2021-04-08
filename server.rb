# frozen_string_literal: true

require 'stripe'
require 'sinatra'

unless ENV['APP_ENV'] == 'production'
  require 'dotenv'
  Dotenv.load('.env')
end
Stripe.api_key = ENV['STRIPE_TEST_SECRET_KEY']
Stripe.api_version = '2020-08-27;boleto_beta=v1'
ENVPOINT_SECRET = ENV['WEBHOOK_SIGNING_SECRET']

set :static, true
set :public_folder, File.dirname(__FILE__)
set :port, 4242

HEROKU_DOMAIN = 'https://glacial-temple-49234.herokuapp.com'
LOCAL_DOMAIN = "http://localhost:#{settings.port}"
YOUR_DOMAIN = ENV['APP_ENV'] == 'production' ? HEROKU_DOMAIN : LOCAL_DOMAIN

get '/' do
  erb :checkout, locals: { pubkey: ENV['STRIPE_TEST_PUBLIC_KEY'] }
end

post '/webhook' do
  event = nil

  logger.info('MY_LOG: Receive webhook request')

  # Verify webhook signature and extract the event
  # See https://stripe.com/docs/webhooks/signatures for more information.
  begin
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    payload = request.body.read
    event = Stripe::Webhook.construct_event(payload, sig_header, ENVPOINT_SECRET)
  rescue JSON::ParserError => e
    # Invalid payload
    logger.error('MY_LOG: webhook Invalid payload')
    return status 400
  rescue Stripe::SignatureVerificationError => e
    # Invalid signature
    logger.error('MY_LOG: webhook Invalid signature')
    return status 400
  end

  logger.info("MY_LOG: EVENT: #{event['type']} #{event.id}")

  begin
    case event['type']
    when 'checkout.session.completed'
      logger.info('MY_LOG: case EVENT checkout.session.completed')
      checkout_session = event['data']['object']

      # TODO: fill in with your own logic
      logger.info("Fulfilling order for #{checkout_session.id}")
    when 'payment_intent.requires_action'
      logger.info('MY_LOG: case EVENT payment_intent.requires_action')
      payment_intent = event['data']['object']

      if payment_intent.next_action.type == 'boleto_display_details'
        payment_intent = Stripe::PaymentIntent.retrieve(
          {
            id: payment_intent.id,
            expand: ['customer']
          }
        )

        # TODO: send voucher emails
        boleto_display_details = payment_intent.next_action.boleto_display_details
        logger.info('MY_LOG: Sending voucher email')
        logger.info("MY_LOG: Send to: #{payment_intent.customer.email}")
        logger.info("MY_LOG: hosted_voucher_url: #{boleto_display_details.hosted_voucher_url}")
        logger.info("MY_LOG: boleto number: #{boleto_display_details.number}")
        logger.info("MY_LOG: expires_after: #{Time.at(boleto_display_details.expires_after)}")
      end
    else
      logger.error('MY_LOG: WTF')
    end
  rescue StandardError => e
    logger.error("MY_LOG: WTF #{e.inspect}")
    return status 200
  end

  return status 200
end

post '/create-checkout-session' do
  content_type 'application/json'

  session = Stripe::Checkout::Session.create(
    payment_method_types: %w[card boleto],
    payment_method_options: {
      boleto: {
        expires_after_days: 14
      }
    },
    line_items: [{
      price_data: {
        unit_amount: 2000,
        currency: 'brl',
        product_data: {
          name: 'Stubborn Attachments',
          images: ['https://i.imgur.com/EHyR2nP.png']
        }
      },
      quantity: 1
    }],
    mode: 'payment',
    success_url: YOUR_DOMAIN + '/success.html',
    cancel_url: YOUR_DOMAIN + '/cancel.html'
  )

  {
    id: session.id
  }.to_json
end
