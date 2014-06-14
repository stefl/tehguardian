require './app'

run Rack::URLMap.new('/' => TehGuardian)