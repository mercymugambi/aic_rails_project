require 'test_helper'

class EventRegistrationTest < ActiveSupport::TestCase
  setup do
    @camp = events(:youth_camp)
  end

  test 'phone_key keeps digits and writes Kenyan numbers one way' do
    {
      '0712 345 678' => '254712345678', '+254 712 345 678' => '254712345678', '254712345678' => '254712345678',
      '712345678' => '254712345678', '(0110) 123-456' => '254110123456', '00254712345678' => '254712345678',
      '+44 20 7946 0958' => '442079460958'
    }.each do |phone, key|
      assert_equal key, EventRegistration.phone_key(phone), phone
    end
    assert_nil EventRegistration.phone_key('')
    assert_nil EventRegistration.phone_key(nil)
  end

  test 'contact details are normalised into keys' do
    registration = EventRegistration.create!(event: @camp, name: ' Mary ', phone: ' 0722 000 111 ',
                                             email: ' Mary@Example.COM ', seats: '')
    assert_equal ['Mary', '0722 000 111', 'Mary@Example.COM', 1],
                 registration.slice(:name, :phone, :email, :seats).values
    assert_equal ['254722000111', 'mary@example.com'], [registration.phone_key, registration.email_key]
  end

  test 'a name and a phone number or email address are needed' do
    registration = EventRegistration.new(event: @camp, name: ' ', phone: ' ', email: '')
    assert_not registration.valid?
    assert_equal ["Name can't be blank", 'Please give a phone number or an email address'],
                 registration.errors.full_messages
  end

  test 'phone, email, name and seats are checked' do
    assert_invalid({ phone: 'call me' }, "Phone number doesn't look right")
    assert_invalid({ phone: '()' }, "Phone number doesn't look right")
    assert_invalid({ phone: '0712 345 678 9012 345 6' }, 'Phone number is too long (maximum is 20 characters)')
    assert_invalid({ email: 'mary@' }, "Email address doesn't look right")
    assert_invalid({ email: "#{'a' * 115}@x.com" }, 'Email address is too long (maximum is 120 characters)')
    assert_invalid({ name: 'a' * 101 }, 'Name is too long (maximum is 100 characters)')
    [0, 11, 'two', '1.5'].each { |seats| assert_invalid({ seats: seats }, 'Seats must be a whole number from 1 to 10') }
  end

  test 'a person signs up once per event, whichever way they write their number or email' do
    assert_invalid({ phone: '+254712345678' }, EventRegistration::ALREADY_REGISTERED) # Grace wrote 0712 345 678
    assert_invalid({ phone: '', email: 'PETER@example.com ' }, EventRegistration::ALREADY_REGISTERED)
  end

  test 'the same person may sign up for another event' do
    other = Event.create!(title: 'Prayer night', category: 'Prayer', description: 'Come and pray.',
                          date: 20.days.from_now.to_date, created_by: users(:super_admin))
    assert EventRegistration.new(event: other, name: 'Grace', phone: '0712 345 678').valid?
  end

  test 'the unique indexes stop duplicates that skip validation' do
    duplicate = EventRegistration.new(event: @camp, name: 'Grace', phone: '+254 712 345 678')
    duplicate.validate # sets phone_key
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  private

  def assert_invalid(overrides, message)
    registration = EventRegistration.new({ event: @camp, name: 'Mary', phone: '0722 000 111' }.merge(overrides))
    assert_not registration.valid?, "expected #{message.inspect}"
    assert_includes registration.errors.full_messages, message
  end
end
