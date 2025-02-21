require 'logger'
require 'fileutils'
require 'tempfile'
require 'mail'

module Scan2Mail
  class Client
    attr_reader :mqtt_client

    attr_reader :base_dir, :images_dir, :out_file
    attr_reader :logger

    attr_accessor :page_count

    delegate :scanner, :format, :color_mode, :resolution, :quality, :emails, to: :'Settings.scan2mail'

    def initialize(mqtt_client, logger: Logger.new($stdout))
      @logger = logger
      @mqtt_client = mqtt_client

      @base_dir = File.join('/', 'tmp', 'scan')
      @images_dir = File.join(base_dir, 'images')
      @out_file = File.join(base_dir, 'out.pdf')

      buttons
    end

    def buttons
      [:flatbed, :simplex, :duplex].each do |type|
        emails.each do |email|
          name = :"scan_#{type}_for_#{email}"
          options = { name: "Scan #{type.to_s.titleize} for #{email}" }
          mqtt_client.discover_and_subscribe_button(name, options) { |_, _| processing(type, email) }
        end
      end
    end

    def processing(type, receiver)
      logger.debug "#{type}, #{receiver}"
      FileUtils.mkdir_p(images_dir)

      scan(type)
      if type == :duplex
        mqtt_client.waiting
        sleep 60
        scan(type, batch_start: 2)
      end
      convert
      send(receiver)
      FileUtils.remove_dir(base_dir)

      mqtt_client.online
    rescue StandardError => e
      mqtt_client.error(e.message)
      logger.error(e)
    end

    def scan(type, batch_start: 1)
      mqtt_client.scanning
      logger.info "Scanning in #{type} mode"
      if type == :flatbed
        `scanimage --device #{scanner} --source Flatbed --mode #{color_mode} --resolution #{resolution} --format #{format} --progress --output-file=#{File.join(images_dir, "out_01.#{format}")}`
      else
        `scanimage --device #{scanner} --source "Automatic Document Feeder" --mode #{color_mode} --resolution #{resolution} --format #{format} --progress --batch=#{File.join(images_dir, "out_%02d.#{format}")} --batch-start=#{batch_start} #{'--batch-double' if type == :duplex}`
      end
      raise 'Scanning failed' unless $?.success?
    end

    def convert()
      mqtt_client.converting
      pages = Dir.entries(images_dir)
                       .sort
                       .map { |f| File.join(images_dir, f) }
                       .select { |f| File.file?(f) && f.end_with?(".#{format}") }
      page_count = pages.size

      raise 'No pages found!' if page_count == 0

      pages.each do |file|
        logger.debug "Prepare #{file}"
        `magick #{file} -fuzz 15% -trim +repage #{file}`
      end

      (file = Tempfile.new(%w[scan .pdf])).close

      logger.debug "Create pdf #{file.to_path}"
      `magick #{ pages.join(' ') } -quality #{quality} #{file.to_path}`
      `gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile=#{out_file} #{file.to_path}`

      raise 'PDF is too big!' if File.size(out_file) >= 2 * 1024 * 1024
      raise 'PDF seems to be broken!' if File.size(out_file) < 20 * 1024
    end

    def send(receiver)
      mqtt_client.sending()
      client = self

      mail = Mail.new do
        self.charset = 'UTF-8'
        from    Settings.mail.from
        to      receiver
        subject Settings.mail.subject

        body <<-EOM
          Im Anhang befindet sich der Scan.
      
          Auflösung: #{client.resolution} dpi
          Farbmodus: #{client.color_mode}
          Anzahl Seiten: #{client.page_count}
          Datei Format: PDF
        EOM

        add_file client.out_file
      end

      mail.delivery_method Settings.mail.method, **Settings.mail.to_h[Settings.mail.method]
      mail.deliver!
    end
  end
end
