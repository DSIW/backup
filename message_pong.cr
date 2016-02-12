require "socket"

abort("Usage: #{$0} host port") unless ARGV.size == 2
host, port = ARGV

NOTIFY_ARGS = ["Ping"]

def handle_client(socket)
  message = socket.gets.try(&.chomp)
  return unless message
  system("notify-send", NOTIFY_ARGS + [message])
end

TCPServer.open(host, port) do |server|
  loop { server.accept { |socket| handle_client(socket) } }
end
