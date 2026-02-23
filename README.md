# Jekyll Paginate V3

Robust, highly configurable pagination for Jekyll.

* Paginate any content source (pages, one collection, many collections, all collections, or everything).
* Filter on any frontmatter key (including nested keys).
* Generate index pages automatically from frontmatter values.

Compatibility modes for (https://github.com/jekyll/jekyll-paginate)-v1 and [jekyll-paginate-v2 ](https://github.com/sverrirs/jekyll-paginate-v2)are also included.

## Quickstart

Include the plugin in your project:

```ruby
# Gemfile
group :jekyll_plugins do
  gem 'jekyll-paginate-v3'
end
```

Enable pagination in your site config (you can also configure how it works, here):

```yaml
# _config.yml
pagination:
  enabled: true
```

Create index pages that should include pagination, specifying what they paginate:

```yaml
# post-index.md - example
---
layout: post-listing
pagination:
  enabled: true
  items: posts
---
```

Then on the layouts that your index pages use:

```liquid
{% for item in paginator.items %}
  <h2><a href="{{ item.url }}">{{ item.title }}</a></h2>
{% endfor %}

{% if paginator.previous_page %}
  <a href="{{ paginator.previous_page_path }}">Newer</a>
{% endif %}

{% if paginator.next_page %}
  <a href="{{ paginator.next_page_path }}">Older</a>
{% endif %}
```

## Configuration

```yaml
pagination:
  enabled: false # global disable

  # Pagination settings - setting them here sets these as defaults for all index pages
  items: posts # what to paginate
  filters: [] # filter which pages to include in pagination

  per_page: 10 # how many items per page
  offset: 0 # skip first x items
  limit: 0 # paginate no more than x items
  trail:
    before: 0
    after: 0

  sort: date desc # how to sort paginated items

  permalink: /page/:num/
  title: ':title - page :num'
  indexpage: index
  extension: html

  indexes:
    location: pages
    generate: []

  compatibility: # optional: v2 or v1
  nested_key_separator: '.' # or ':'
  keywords:
    pages: pages
    all: all
    everything: everything
    items: items # set to posts for v2-style payload
  equivalents:
    - [tag, tags]
    - [category, categories]
```

## Index Pages (Pagination Templates)

Any page/document becomes an index when it has:

```yaml
pagination:
  enabled: true
```

Index discovery is controlled by `pagination.indexes.location`, which uses the shared search format.

## Search Format (`items`, `indexes.location`, `indexes.generate[].items`)

Accepted forms:

1. String: `pages`, `posts`, `all`, `everything`
2. Hash: `{ posts: '*' }`, `{ pages: 'blog/*' }`
3. Array of strings/hashes
4. Comma-delimited string array: `pages, posts`

Special keywords (`pages`, `all`, `everything`) are configurable via `pagination.keywords`.

## Filtering

Filters use `pagination.filters`:

```yaml
pagination:
  enabled: true
  items: posts
  filters:
    category: news
    locale: en_GB
    author.name: /^a/i
    rating:
      min: 3
      max: 5
```

Supported filter forms per key:

- scalar (`news`, `42`, `2026-01-01`)
- comma/semicolon list (`news, blog`)
- array
- regex literal (`/^s/`)
- range hash (`{min: 2, max: 5}`)
- grouped boolean hash (`{list: [...], join: and|or}`)

Nested keys use `pagination.nested_key_separator` (`.` by default).

## Sorting

`sort` supports multi-level sort definitions:

```yaml
pagination:
  sort:
    - featured desc
    - author.name asc empty:last
    - date desc
```

Syntax per entry: `field [options]`

Options:

- direction: `asc`/`ascending` or `desc`/`descending`
- empty handling: `empty:first` or `empty:last`

Legacy `sort_field` and `sort_reverse` are up-migrated in compatibility mode.

## Generated Indexes (`pagination.indexes.generate`)

Automatically generate index templates from frontmatter values:

```yaml
pagination:
  indexes:
    location: pages
    generate:
      - items: posts
        index: tag
        layout: autopage_tags.html
        permalink: /tag/:tag/
        title: 'Posts tagged :tag'

      - items: products
        index: category, subcategory
        layouts: [autopage_category.html]
        filter: /^s/
        frontmatter:
          section: catalogue
```

Important behaviour:

- `index` may be single or multi-level.
- `filter` is shorthand for applying the same filter to each indexed key.
- generated templates include `pagination.enabled: true` and are then paginated by the core generator.
- generated templates can be created as pages or collection docs via `location`.
- placeholders in generated `permalink`/`title` include each indexed key (for example `:owner.name`).

## Compatibility

### `compatibility: v2`

- keeps v2-style paginator payload naming by default (`paginator.posts`),
- up-migrates legacy shortcut keys (`collection`, `category`, `tag`, `locale`),
- up-migrates old AutoPages config (`site.autopages`) into `pagination.indexes.generate`.

### `compatibility: v1`

- runs legacy jekyll-paginate-style logic,
- reads `paginate` and `paginate_path` and up-migrates them,
- uses `index.html` hierarchy selection and classic pager behaviour.

If `paginate` is present but compatibility is unset, v1 compatibility is auto-enabled with a warning.

## Paginator Payload

`page.paginator` (and `paginator` in templates) includes:

- `items`, `total_items`
- `page`, `per_page`, `total_pages`
- `previous_page`, `previous_page_path`
- `next_page`, `next_page_path`
- `first_page`, `first_page_path`
- `last_page`, `last_page_path`
- `page_trail`

If `pagination.keywords.items` is changed (for example to `posts`), matching aliases are also included (`posts`, `total_posts`).

## Notes

- Hidden content (`hidden: true`) is excluded from pagination items.
- Index pages are never included in their own paginated item sets.
- Generated pagination pages after page 1 are marked with `page.autogen: jekyll-paginate-v3`.


## Acknowledgements

This gem drew heavy inspiration from the [jekyll-paginate-v2](https://github.com/sverrirs/jekyll-paginate-v2) gem which itself was based on the original design of [jekyll-paginate](https://github.com/jekyll/jekyll-paginate).