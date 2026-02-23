# Jekyll Test Harness

Simple integration testing for Jekyll plugins. Extends RSpec or Minitest with helper methods for building a real Jekyll site, with your plugin available, to test how it actually runs within Jekyll.


## Setup

```ruby
# Gemfile
group :test do
  gem 'jekyll-test-harness'
  gem 'rspec', '~> 3.13' # if using RSpec
  gem 'minitest', '>= 5.0' # if using Minitest
end
```

Load the harness into RSpec:

```ruby
# spec/spec_helper.rb
require 'rspec'
require 'jekyll_test_harness'
require 'my_plugin'

RSpec.configure do |config|
  JekyllTestHarness.install!(framework: :rspec)
end
```

Load the harness into Minitest:

```ruby
# test/test_helper.rb
require 'minitest/autorun'
require 'jekyll_test_harness'
require 'my_plugin'

JekyllTestHarness.install!(framework: :minitest)
```

`JekyllTestHarness.install!` auto-detects your test framework. However this can also be configured explicitly along with other global configuration:

```ruby
JekyllTestHarness.install!(
  framework: :rspec,
  failures: :clean,          # or :keep
  output: nil                # nil => system temp, or project-relative string like 'tmp/jekyll-sites'
)
```

Options:

- `failures:`
  - `:clean` (default): remove temporary site directories after failures.
  - `:keep`: keep failed build directories for debugging.
- `output:`
  - `nil` (default): build under system temp.
  - relative path: resolved from the project root captured during `install!`.
  - absolute path: used as-is.


## Test DSL

After calling `install!`, your examples/tests get these helper methods:

- `jekyll_build(...) { |site, files| ... }`
- `jekyll_config(hash = nil, file: nil)`
- `jekyll_files { ... }`
- `jekyll_blueprint(config:, files:)`
- `jekyll_merge(base, new)`

### `jekyll_build`

Builds a fresh throwaway Jekyll site for one test, runs a real Jekyll build (`Jekyll::Site#process`), and yields:

- `site`: the built `Jekyll::Site` object (collections, documents, metadata, etc.)
- `files`: inspect the files that were output by Jekyll

```ruby
jekyll_build(blueprint = nil, config: nil, files: nil) do |site, files|
  # assertions
end
```

No default scaffold is written automatically. Supply your own files/layouts/content.

### `files` object

`jekyll_build` yields a `files` helper with:

- `dir`:
  absolute output directory.
- `path(relative_path)`:
  absolute path under output directory.
- `read(relative_path)`:
  reads file from output directory.
- `list(root = nil)`:
  returns output file paths relative to output directory.

Source inspection methods are also available:

- `source_dir`
- `source_path(relative_path)`
- `source_read(relative_path)`
- `source_list(root = nil)`

`relative_path` arguments are validated to prevent path traversal outside the temporary site.

### `jekyll_config(hash = nil, file: nil)`

Builds config data and appends it to the internal config buffer.

- `hash` can be provided directly.
- `file:` loads YAML from a fixture path relative to project root.
- if both are provided, `hash` merges over loaded fixture YAML.

Each call returns the resolved hash and merges it into the buffer.

When calling `jekyll_build`, if `config:` is omitted, the buffered value from `jekyll_config` is used. Either way, the buffer is then flushed.

Safety rule:

- user-provided `source` and `destination` config keys are ignored.
- the harness always enforces its own temporary `source`/`destination` paths.
- a warning is emitted when either key is provided.

### `jekyll_files { ... }`

Use this helper to specify the files within the test Jekyll site. Builds nested file hashes with DSL methods and appends result to the internal files buffer.

```ruby
files = jekyll_files do
  folder '_layouts' do
    file 'default.html' do
      '<html><body>{{ content }}</body></html>'
    end
  end
  file 'index.md' do
    frontmatter('layout' => 'default')
    contents('Hello from buffered files')
  end
end
```

- `folder(name) { ... }` can contain nested `folder`/`file` calls.
- `file(name) { ... }` block defines file contents.
- Inside a `file` block, these helpers are available:
  - `frontmatter(hash = nil, file: nil)`
    - YAML-dumps hash between `---` separators.
    - `file:` loads YAML fixture first, then merges inline hash over it.
  - `contents(string = nil, file: nil)`
    - passes string through directly.
    - `file:` loads raw fixture text.
- If `frontmatter`/`contents` are not used, file block can directly return:
  - `String` (written directly)
  - `Array` (joined with newlines)
  - `Hash` (YAML-dumped)

Each `jekyll_files` call both returns the generated hash and merges it into the internal files buffer. The returned hash could be passed to `jekyll_build` or `jekyll_blueprint`.

When calling `jekyll_build`, if `files:` is omitted, the buffered value from `jekyll_files` is used. Either way, the buffer is then flushed.

### `jekyll_blueprint(config:, files:)`

Creates a reusable blueprint object that stores config and file hashes for composition.

```ruby
base_blueprint = jekyll_blueprint(
  config: { 'my_plugin' => { 'mode' => 'base' } },
  files: {
    '_layouts' => { 'default.html' => '<html><body>{{ content }}</body></html>' },
    'index.md' => "---\nlayout: default\n---\nBase body\n"
  }
)
```

A blueprint can be passed as the first parameter of `jekyll_build`. If `config` or `files` are also passed, these are merged over the blueprint.

### `jekyll_merge(base, new)`

Used for deep merges:

- Hash + Hash => deep hash merge
- JekyllBlueprint + JekyllBlueprint => new merged blueprint.


## Example

```ruby
RSpec.describe 'my plugin integration' do
  it 'renders expected output' do
    jekyll_config(file: 'spec/fixtures/jekyll/base_config.yml')

    jekyll_files do
      folder '_layouts' do
        file 'default.html' do
          '<html><body>{{ content }}</body></html>'
        end
      end

      folder '_posts' do
        file '2026-01-01-demo.md' do
          frontmatter('layout' => 'default', 'permalink' => '/docs/demo.html')
          contents('Hello')
        end
      end
    end

    jekyll_build do |site, files|
      post = site.collections.fetch('posts').docs.first
      html = files.read('docs/demo.html')
      expect(post).not_to be_nil
      expect(html).to include('Hello')
    end
  end
end
```