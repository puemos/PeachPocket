require 'json'
require 'open3'
require 'timeout'

bridge = File.expand_path('../build/Lidlight.app/Contents/Resources/LidlightBridge', __dir__)
Open3.popen3(bridge) do |input, output, errors, process|
  sequence = 0
  request = lambda do |command, duration = 0|
    sequence += 1
    input.puts(JSON.generate(id: sequence, command: command, duration: duration))
    input.flush
    line = Timeout.timeout(4) { output.gets }
    raise 'Bridge ended before replying' unless line
    reply = JSON.parse(line)
    raise 'Reply ID mismatch' unless reply['id'] == sequence
    raise 'Helper needs setup/update for the stable bridge' unless reply['status']
    reply['status']
  end
  status = request.call('ping')
  puts "PASS signed bridge talks to helper (active=#{status['active']}, disabled=#{status['disabled']})"
  if ARGV.include?('--exercise-session')
    raise 'An existing awake session is running; leaving it untouched' if status['active'] || status['disabled']
    begin
      status = request.call('start', 5)
      raise "Start failed: #{status['message']}" unless status['active'] && status['disabled']
      puts 'PASS session starts without another authorization prompt'
      status = request.call('ping')
      raise 'Heartbeat failed' unless status['active']
      status = request.call('stop')
      raise "Restore failed: #{status['message']}" unless !status['active'] && status['disabled'] == false
      puts 'PASS session stops and normal sleep is restored'
    ensure
      request.call('stop') rescue nil
    end
  end
  if ARGV.include?('--exercise-disconnect')
    status = request.call('ping')
    raise 'An existing awake session is running; leaving it untouched' if status['active'] || status['disabled']
    status = request.call('start', 5)
    raise 'Could not start disconnect-recovery test' unless status['active']
  end
  input.close
  Timeout.timeout(4) { process.value }
  if ARGV.include?('--exercise-disconnect')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    loop do
      settings, result = Open3.capture2('/usr/bin/pmset', '-g')
      break if result.success? && settings.match?(/SleepDisabled\s+0/)
      raise 'Bridge closure failed to restore sleep within two seconds' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.1
    end
    puts 'PASS app-pipe closure restores sleep within two seconds'
  end
  puts 'PASS bridge exits on app pipe closure'
end
