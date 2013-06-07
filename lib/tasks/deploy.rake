desc "Renders all ERB files in config"
task :deploy do
  require 'pathname'
  require 'erubis'
  require 'tilt'

  ENV['APP_DIR']  ||= Pathname.new("#{File.dirname(__FILE__)}/../..").cleanpath.to_s
  ENV['RUBY']     ||= File.join(Config::CONFIG['bindir'],
                  Config::CONFIG['ruby_install_name']).sub(/.*\s.*/m, '"\&"')

  Dir["#{File.dirname(__FILE__)}/../../config/*.erb"].each do |infile|
    puts "Rendering #{File.basename infile}..."
    File.open(infile.gsub(/\.erb$/i,''), 'w') do |outfile|
      outfile.write Tilt.new(infile).render
    end
  end
end
