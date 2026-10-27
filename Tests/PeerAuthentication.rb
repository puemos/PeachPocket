require 'json'
require 'open3'
require 'timeout'
require 'tmpdir'
require 'fileutils'

def ping(client)
  Open3.popen3(client) do |input, output, errors, process|
    input.puts(JSON.generate(id: 1, command: 'ping', duration: 0))
    input.flush
    reply = JSON.parse(Timeout.timeout(4) { output.gets })
    input.close
    Timeout.timeout(4) { process.value }
    reply
  end
end

bridge = File.expand_path('../build/PeachPocket.app/Contents/Resources/PeachPocketBridge', __dir__)
raise 'Install or update the helper before running this check' unless ping(bridge)['status']
Dir.mktmpdir('peachpocket-untrusted-') do |directory|
  client = File.join(directory, 'untrusted-client')
  FileUtils.cp(bridge, client)
  output, error, result = Open3.capture3('/usr/bin/codesign', '--force', '--options', 'runtime', '--identifier', 'local.peachpocket.test.untrusted', '--sign', '-', client)
  raise "Could not prepare test client: #{output} #{error}" unless result.success?
  raise 'Helper accepted a client with the wrong code signature' if ping(client)['status']
  puts 'PASS trusted bridge connects and helper rejects a differently signed same-user client'
end
