require_relative '../lib/env_reader'
require_relative '../lib/version_file_reader'
require_relative '../lib/version_validator'

def get_template(format)
  ERB.new(File.read("#{File.dirname(__FILE__)}/../templates/pipeline_config.#{format.downcase}.erb"), nil, '-')
end

def validate_config_format(format)
  acceptable_formats = ['json', 'yaml']
  fail "Invalid config format '#{format}'. Acceptable formats are #{acceptable_formats}" unless acceptable_formats.include?(format.downcase)
  format.downcase
end

def get_template_name(repo_name)
  {
      'plugin-api.go.cd' => 'plugin-api-docs',
      'api.go.cd'        => 'api.go.cd',
      'developer.go.cd'  => 'gocd-developer-docs',
      'docs.go.cd'       => 'gocd-help-docs'
  }[repo_name]
end

def get_pipeline_group_name(repo_name)
  {
      'plugin-api.go.cd' => 'plugin-api-docs ',
      'api.go.cd'        => 'gocd-api-docs',
      'developer.go.cd'  => 'gocd-developer-docs',
      'docs.go.cd'       => 'gocd-help-docs'
  }[repo_name]
end

at_exit do
  # rm_rf 'build'
end

desc 'Create pipeline for given repository'
task :create_pipeline do
  file_extensions_map    = {
      'json' => 'gopipeline.json',
      'yaml' => 'gocd.yaml'
  }
  pipeline_config_format = validate_config_format(Env.get_or_error('PIPELINE_CONFIG_FORMAT'))
  go_version             = VersionFileReader.go_version
  git_username           = Env.get_or_error('GITHUB_USER')
  git_token              = Env.get_or_error('GITHUB_TOKEN')
  repo_name              = Env.get_or_error('REPO_NAME').to_s.downcase
  pipeline_group_name    = Env.get('PIPELINE_GROUP_NAME') || get_pipeline_group_name(repo_name)
  template_name          = Env.get('TEMPLATE_NAME') || get_template_name(repo_name)

  fail 'Must specify environment variable PIPELINE_GROUP_NAME' if pipeline_group_name.to_s.empty?
  fail 'Must specify environment variable TEMPLATE_NAME' if template_name.to_s.empty?

  pipeline_name         = "#{repo_name}-release-#{go_version}"
  pipeline_material_url = "https://git.gocd.io/git/gocd/#{repo_name}"
  git_branch            = "release-#{go_version}"

  erb                      = get_template(pipeline_config_format)
  pipeline_config_content  = erb.result(binding)
  pipeline_config_filename = "#{go_version}.#{file_extensions_map[pipeline_config_format]}"
  repo_url                 = "https://#{git_username}:#{git_token}@github.com/gocd/#{repo_name}"

  rm_rf 'build'
  sh("git clone #{repo_url} build --branch master --depth 1 --quiet")

  cd 'build' do
    mkdir 'build_gocd_pipelines' unless Dir.exist?('build_gocd_pipelines')
    pipeline_config_file_path = "build_gocd_pipelines/#{pipeline_config_filename}"
    open(pipeline_config_file_path, 'w') do |file|
      file.puts(pipeline_config_content)
    end

    response = %x[git status]
    unless response.include?('nothing to commit')
      sh("git add #{pipeline_config_file_path}")
      sh("git commit -m \"Add config repo pipeline named '#{pipeline_name}' in file '#{pipeline_config_filename}'\"")
      sh("git push origin master")
    end
  end
end

desc 'Add the current release to docs pipeline'
task :add_release_to_docs_pipeline do
  go_version   = VersionFileReader.go_version
  go_previous_version   = VersionFileReader.previous_version
  git_username = Env.get_or_error('GITHUB_USER')
  git_token    = Env.get_or_error('GITHUB_TOKEN')
  repo_name    = Env.get_or_error('REPO_NAME').to_s.downcase

  repo_url = "https://#{git_username}:#{git_token}@github.com/gocd/#{repo_name}"

  rm_rf 'build'
  sh("git clone #{repo_url} build --branch master --depth 1 --quiet")

  cd 'build' do
    pipeline_file = 'build.gocd.groovy'
    if File.exist?(pipeline_file)
      content = File.read(pipeline_file)
      content.gsub!("'#{go_previous_version}'", "'#{go_previous_version}','#{go_version}'")

      File.open(pipeline_file, "w") {|file| file.puts content}

      response = %x[git status]
      unless response.include?('nothing to commit')
        sh("git add .")
        sh("git commit -m \"Add release '#{go_version}' to older releases\"")
        sh("git push origin master")
      end
    end
  end
end
