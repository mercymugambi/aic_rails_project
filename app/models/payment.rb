class Payment < ApplicationRecord
  CONTRIBUTION_TYPES = %w[donation offering tithe other].freeze
  STATUSES = %w[pending success failed cancelled].freeze

  validates :phone_number,
            presence: true,
            format: { with: /\A254[17]\d{8}\z/, message: 'must be a valid Kenyan phone number' }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :contribution_type, presence: true, inclusion: { in: CONTRIBUTION_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :successful, -> { where(status: 'success') }
  scope :by_type, ->(type) { where(contribution_type: type) }
end
