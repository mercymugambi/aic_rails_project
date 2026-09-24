class Event < ApplicationRecord
  belongs_to :created_by, class_name: 'User'

  validates :title, presence: true
  validates :description, presence: true
  validates :date, presence: true
end
