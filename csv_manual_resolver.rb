require 'csv'

class CsvManualResolver
  STATUS = {
    match: 'match',
    check: 'check' }.freeze
  MATCHED_VALUE = '1'.freeze
  EMPTY_MATCH = ''.freeze

  attr_reader :finded_data

  def read_data!
    @finded_data = try_to_read_files(find_file_names(STATUS[:match]))
  end

  def prepare_data_to_write!(items, names)
    @prepare_data_to_write ||= []
    @prepare_data_to_write << prepare_data(items, names)
  end

  def write_file
    CSV.open("#{file_name(STATUS[:wait])}.csv", 'w') do |row|
      @prepare_data_to_write.each { |data| row << data }
    end
  end

  def find_items(items)
    items.each do |item|
      return item if @finded_data.include?(item)
    end
    nil
  end

private

  def try_to_read_files(files_names)
    files_names.each_with_object({}) do |file_name, mem|
      CSV.open(file_name, 'r') do |row|
        mem[row[0]] = result[row[-2]] if row[1] == MATCHED_VALUE
      end
    end
  end

  def prepare_data(items, names)
    result = []
    items.each_with_index do |item, index|
      names[index].each do |name_item|
        result << [
          item.attributes['data_registered_name'],
          EMPTY_MATCH,
          name_item,
          item.attributes['smpc_chap1']]
      end
    end
    result
  end

  def file_name(status)
    "smpc_matches_#{status}"
  end

  def find_file_names(status)
    Dir[File.join('.', file_name(status), '*')].sort.map do |file|
      file
    end
  end

  def compute_file_name(item)
    File.join(__dir__, "#{item.attributes['data_registered_name']}.csv")
  end
end
