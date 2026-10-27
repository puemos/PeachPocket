require 'open3'

binary = ARGV.fetch(0)
cases = {
  'empty sequence' => [''],
  'unsupported strength' => ['99:100'],
  'negative strength' => ['-6:100'],
  'zero delay' => ['6:0'],
  'negative delay' => ['6:-100'],
  'trailing separator' => ['6:100,'],
  'extra arguments' => ['6:100', 'extra'],
  'excessive duration' => [(['6:600'] * 5).join(',')],
  'excessive tap count' => [(['6:60'] * 25).join(',')]
}
cases.each do |name, arguments|
  output, error, status = Open3.capture3(binary, *arguments)
  raise "FAIL #{name}: #{output} #{error}" unless status.exitstatus == 2
  puts "PASS actuator rejects #{name}"
end
