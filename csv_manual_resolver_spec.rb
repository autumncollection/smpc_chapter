require 'rspec'
require 'ostruct'
require 'pry'

require_relative 'csv_manual_resolver'

describe CsvManualResolver do
  def item_object(name, smpc)
    OpenStruct.new(attributes: { 'data_registered_name' => name, 'smpc_chap1' => smpc })
  end

  describe '#perform' do
    let(:items) do
      [
        item_object('name 1', 'smpc 1'),
        item_object('name 2', 'smpc 2')
      ]
    end

    let(:names) do
      [
        ['name 1 something 1', 'name 1 something 2', 'name 1 something 3'],
        ['name 2 something 1', 'name 2 something 2']
      ]
    end

    subject { described_class.perform(items, names) }

    it { is_expected.to be(true) }
  end
end
