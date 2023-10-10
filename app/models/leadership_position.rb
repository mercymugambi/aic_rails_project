class LeadershipPosition < ApplicationRecord
    validates :position_name, presence: true
    validates :position_code, uniqueness: true

    
    has_many :members
  end