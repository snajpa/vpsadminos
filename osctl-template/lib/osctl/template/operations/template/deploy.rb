require 'osctl/template/operations/base'

module OsCtl::Template
  class Operations::Template::Deploy < Operations::Base
    # @return [Operations::Template::Build]
    attr_reader :build

    # @return [String]
    attr_reader :repo_dir

    # @return [Array<String>]
    attr_reader :tags

    # @param build [Operations::Template::Build]
    # @param repo_dir [String]
    # @param tags [Array<String>]
    def initialize(build, repo_dir, tags: [])
      @build = build
      @repo_dir = repo_dir
      @tags = tags
    end

    def execute
      Operations::Repository::Create.run(repo_dir)

      t = build.template

      Operations::Repository::AddImage.run(
        repo_dir,
        {
          tar: build.output_tar,
          zfs: build.output_stream,
        },
        {
          distribution: t.distribution,
          version: t.version,
          arch: t.arch,
          vendor: t.vendor,
          variant: t.variant,
        },
        tags,
      )
    end
  end
end
