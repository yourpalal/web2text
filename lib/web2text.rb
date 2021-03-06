require 'anemone'
require 'nokogiri'

require 'optparse'


module Web2Text
  class Error < RuntimeError
    def initialize(msg)
      super msg
    end
  end

  class CommandError < Error
    def initialize(msg)
      super msg
    end
  end

  def self.parse_cli(args)
    options = {
      query: "body",
      sleep: 0.0,
      avoid: [],
      focus: [],
      formatter: LinePrinter,
      ignore_robots_txt: false,
      out: $stdout,
    }

    args = args.clone

    OptionParser.new do |opts|
        opts.banner = "Usage: web2text [options] http://example.com/"

        opts.on("-q", "--css", "--query=CSS_QUERY", String) do |q|
          options[:query] = q
        end

        opts.on("-s [OPTIONAL]", "--sleep [OPTIONAL]", Float, "Delay between requests. Default 1, -s sets to 1.") do |n|
          options[:sleep] = n || 1.0
        end

        opts.on("--avoid x,y,z", Array, "List of paths to avoid when crawling. These paths and everything below them will be ignored.") do |avoid|
          options[:avoid] = avoid
        end

        opts.on("--focus x,y,z", Array, "List of paths to process when crawling. Only these paths and pages below them will be processed") do |focus|
          options[:focus] = focus
        end


        opts.on("--lines [web2.txt]", String, "One line per page. Can print to std out or a file.") do |f|
          options[:formatter] = LinePrinter
          options[:out] = if f then File.open(f, 'w') else $stdout end
        end

        opts.on("--files out/", String, "One file per page. Following website structure, in the specified directory.") do |o|
          options[:formatter] = FilePrinter
          options[:out] = Pathname(o)

          if options[:out].exist? and !options[:out].directory? then
            raise Web2Text::CommandError.new 'argument to --files must be a directory'
          end
        end

        opts.on("--bad-robot", "Ignore robots.txt") do
          options[:ignore_robots_txt] = true
        end

        opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
        end
    end.parse! args

    if args.length != 1 then
      raise Web2Text::CommandError.new 'incorrect number of arguments!'
    end

    options[:url] = args[0]
    options
  end

  def self.do_crawl(options)
    crawl = Crawl.new options[:url], options[:avoid], options[:focus]
    crawler = Crawler.new crawl, options[:query]
    formatter = options[:formatter].new crawl, options[:out]

    Anemone.crawl(crawl.url, :obey_robots_txt => !options[:ignore_robots_txt]) do |anemone|
        anemone.focus_crawl do |page|
          crawl.filter page.links
        end

        anemone.on_every_page do |page|
            STDERR.puts page.url

            # ignore redirects
            code = page.code || 200
            if 300 <= code and code < 400
              next
            elsif !crawl.focus? page.url
              next
            elsif page.doc.nil?
              STDERR.puts "ERR: Failed to retrieve #{page.url}"
              next
            end

            plain = crawler.doc_as_plaintext page.doc
            formatter.append plain, page.url
            sleep options[:sleep]
        end

        anemone.after_crawl do
          formatter.close
        end
    end
  end
end

require 'web2text/crawl'
require 'web2text/crawler'
require 'web2text/formatters'
