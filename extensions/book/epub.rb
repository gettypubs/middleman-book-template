require "fileutils"
require "nokogiri"
require "haml"
require "time"

module Book
  class Epub
    attr_reader :book, :chapters, :template_path, :output_path, :metadata

    # Pass in an array of chapter objects on initialization
    # Pass in a reference to the parent Book extension that created the epub object
    def initialize(book, chapters, output_path)
      @book        = book
      @chapters    = chapters
      @output_path = output_path
    end

    # Run this process to build the complete epub file
    def build(sitemap)
      build_epub_dir
      copy_images(sitemap)
      build_container
      build_cover_page
      build_toc_nav
      build_chapters
      build_epub_css
      build_toc_ncx
      build_page_from_template("content.opf")
    end

    # Load a template from the book/templates directory
    # Returns a Haml::Engine object ready to render
    def load_template(file)
      path = "extensions/book/templates/" + file
      Haml::Engine.new(File.read(path), :format => :xhtml)
    end

    private

    def clean_directory(dirname)
      valid_start_chars = /[A-z]/
      valid_start_chars.freeze
      return false unless dirname.chr.match(valid_start_chars)
      FileUtils.rm_rf(dirname) if Dir.exist?(dirname)
      Dir.mkdir(dirname)
    end

    def build_epub_dir
      oebps_subdirs = %w(assets assets/images assets/stylesheets assets/fonts)
      Dir.chdir(output_path) do
        FileUtils.rm_rf(".")
        ["META-INF", "OEBPS"].each { |dir| clean_directory(dir) }
        Dir.chdir("OEBPS") do
          oebps_subdirs.each { |dir| clean_directory(dir) }
        end
      end
    end

    # Copy image resources from the Middleman sitemap into the epub package
    # and add their information to the parent Book object's @manifest
    # TODO: streamline this method, it's too complex
    def copy_images(sitemap)
      resources = sitemap.resources
      images = resources.select { |r| r.path.match("assets/images/*") }
      images.reject! { |r| r.path.to_s == "assets/images/.keep" }

      Dir.chdir(output_path + "OEBPS/assets/images") do
        images.each_with_index do |image, index|
          filename = image.file_descriptor.relative_path.basename
          item = { :href => image.file_descriptor.relative_path,
                   :id => "img_#{index}",
                   :media_type => image.content_type }

          if image.file_descriptor.relative_path.basename.to_s == book.cover
            item[:properties] = "cover-image"
          end

          File.open(filename, "w") { |f| f.puts image.render }
          @book.manifest << item
        end
      end
    end

    def build_page_from_template(filename)
      template = load_template("#{filename}.haml")
      Dir.chdir(output_path + "OEBPS/") do
        File.open(filename, "w") { |f| f.puts template.render(Object.new, :book => book) }
      end
    end

    # Various Build Methods
    # These methods write one or more files at a specific location

    def build_container
      template = load_template("container.xml.haml")
      Dir.chdir(output_path + "META-INF/") do
        File.open("container.xml", "w") { |f| f.puts template.render }
      end
    end

    def build_cover_page
      return false unless book.cover
      build_page_from_template("cover.xhtml")

      item = { :id => "coverpage",
               :href       => "cover.xhtml",
               :media_type => "application/xhtml+xml" }

      navpoint = { :src => "cover.xhtml",
                   :play_order => 0,
                   :id => "coverpage",
                   :text => "Cover" }

      @book.navmap << navpoint
      @book.manifest << item
    end

    def build_chapters
      Dir.chdir(output_path + "OEBPS/") do
        chapters.each_with_index do |c, index|
          File.open("#{c.title.slugify}.xhtml", "w") { |f| f.puts c.format_for_epub }
          item = c.generate_item_tag
          navpoint = c.generate_navpoint
          navpoint[:play_order] = index + 2    # start after cover, toc
          navpoint[:id] = "np_#{index}"
          @book.navmap << navpoint
          @book.manifest << item
        end
      end
    end

    def build_epub_css
      # TODO: Allow custom user css to be appended to this file
      template = File.read("extensions/book/templates/epub.css")
      Dir.chdir(output_path + "OEBPS/assets/stylesheets") do
        File.open("epub.css", "w") { |f| f.puts template }
      end

      item = {
        :id         => "epub.css",
        :href       => "assets/stylesheets/epub.css",
        :media_type => "text/css"
      }

      @book.manifest << item
    end

    def build_toc_ncx
      build_page_from_template("toc.ncx")

      item = {
        :id         => "toc.ncx",
        :href       => "toc.ncx",
        :media_type => "application/x-dtbncx+xml"
      }

      @book.manifest << item
    end

    def build_toc_nav
      build_page_from_template("toc.xhtml")

      item = { :id         => "toc",
               :href       => "toc.xhtml",
               :media_type => "application/xhtml+xml",
               :properties => "nav" }

      navpoint = { :src => "toc.xhtml",
                   :play_order => 1,
                   :id => "toc",
                   :text => "Contents" }

      @book.navmap << navpoint
      @book.manifest << item
    end

  end
end
