# frozen_string_literal: true

# TODO(plural): add a side code to faction.
class Faction < ApplicationRecord
  self.primary_key = :code

  has_many :cards,
    :primary_key => :code,
    :foreign_key => :faction_code
end
