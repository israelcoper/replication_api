class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  self.abstract_class = true

  connects_to database: { writing: :primary, reading: :primary_replica }
end
