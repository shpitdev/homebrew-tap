# Execute the real install method with a minimal filesystem-backed Homebrew DSL.
# This is a Linux-compatible packaging regression, not a native brew install test.
require "fileutils"
require "open3"
require "pathname"

class CurlDownloadStrategy; end

class InstallPath < Pathname
  def install(sources)
    mkpath
    FileUtils.mv(sources, to_s)
  end

  def install_symlink(*sources)
    mkpath
    sources.each do |source|
      links = source.is_a?(Hash) ? source : {source => source.basename}
      links.each { |target, name| FileUtils.ln_s(target, self / name) }
    end
  end
end

class Formula
  class << self
    def desc(*); end
    def homepage(*); end
    def version(*); end
    def revision(*); end
    def license(*); end
    def on_macos; end
    def test; end
  end

  attr_reader :libexec, :bin

  def initialize(prefix)
    @libexec = InstallPath.new(File.join(prefix, "libexec"))
    @bin = InstallPath.new(File.join(prefix, "bin"))
  end
end

def contents(root)
  Dir.glob("**/*", base: root).sort.to_h do |entry|
    path = File.join(root, entry)
    [entry, File.directory?(path) ? :directory : [File.binread(path), File.stat(path).mode & 0o777]]
  end
end

formula_path, stage, prefix = ARGV
load formula_path
expected = contents(stage)
expected["bin/foundry-cli-go"] = expected.delete("foundry-cli")
formula = FoundryCli.new(prefix)
Dir.chdir(stage) { formula.install }
raise "Install changed archive contents or created extra files" unless contents(formula.libexec) == expected

targets = {
  "foundry-cli-go" => "go", "foundry-cli" => "go", "fcli" => "go", "foundry-cli-ts" => "ts",
}
raise "Unexpected public names" unless formula.bin.children.map { |path| path.basename.to_s }.sort == targets.keys.sort

targets.each do |name, cli|
  launcher = formula.bin / name
  raise "Missing executable symlink: #{name}" unless launcher.symlink? && launcher.executable?
  raise "Incorrect executable target: #{name}" unless launcher.realpath == formula.libexec / "bin/foundry-cli-#{cli}"

  output, status = Open3.capture2e(launcher.to_s, "version")
  raise "Installed fixture command failed: #{name}: #{output}" unless status.success? && output == "#{cli} fixture\n"
end
