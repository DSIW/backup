require "socket"

abort("Usage: #{$0} host port message") unless ARGV.size == 3
host, port, message  = ARGV

TCPSocket.open(host, port) { |socket| socket.puts(message) }
