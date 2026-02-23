# Jekyll Paginate V3

Robust, highly configurable pagination for Jekyll.

* Paginate any content source (pages, one collection, many collections, all collections, or everything).
* Filter on any frontmatter key (including nested keys).
* Generate pagination templates automatically from frontmatter values.

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

Create pagination templates, specifying what they paginate:

```yaml
# post-index.md - example
---
layout: post-listing
pagination:
  enabled: true
  items: posts
---
```

Then on the layouts used by the generated indexes:

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
  split: "," # delimiter used where array-like fields accept delimited strings

  # Pagination settings - setting them here sets these as defaults for all templates
  items: posts # what to paginate
  filters: {} # filter which pages to include in pagination

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

  templates:
    location: pages
    generate: []

  compatibility: # optional: v2 or v1
  nested_key_separator: '.' # or ':'
  keywords:
    pages: pages
    all: all
    everything: everything
    now: now
    items: items # set to posts for v2-style payload
  equivalents:
    - [tag, tags]
    - [category, categories]
```

## Pagination Templates

Any page/document becomes a template when it has:

```yaml
pagination:
  enabled: true
```

Template discovery is controlled by `pagination.templates.location`, which uses the shared search format.

## Search Format (`items`, `templates.location`, `templates.generate[].items`)

Accepted forms:

1. String: `pages`, `posts`, `all`, `everything`
2. Hash: `{ posts: '*' }`, `{ pages: 'blog/*' }`
3. Array of strings/hashes
4. Delimited string array: `pages, posts` (delimiter comes from `pagination.split`)

Special keywords (`pages`, `all`, `everything`) are configurable via `pagination.keywords`.

## Filtering

Filters use `pagination.filters`, which must be a hash:

```yaml
pagination:
  filters:
    <frontmatter key>: <filter definition>
```

Each filter key is applied independently, then combined with logical `AND` across keys.

Example:

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

### Canonical Longhand Form

All filter definitions are normalised into this recursive group shape:

```yaml
filters:
  <key>:
    include: <filter-definition-list>
    exclude: <filter-definition-list>
    join: or # or and
```

- `include` and `exclude` are both optional, but at least one must be present.
- `join` controls how sibling entries are combined (`or` default, `and` optional).
- `exclude` entries are negated after combination.

`include`/`exclude` accept:
- single scalar/hash (treated as one entry),
- delimited string (split using `pagination.split`),
- array of filter definitions.

Each entry can itself be a scalar, scalar hash, range hash, array, delimited string, or another group hash (recursive).

Example recursive definition:

```yaml
filters:
  category:
    include:
      - /^s/
      - include:
          min: 5
      - exclude: bob, jane
        join: or
    join: and
```

### Shortcut Forms (Per Key)

These are all shortcuts to the longhand group above with `join: or`.

1. Scalar shortcut

```yaml
filters:
  category: news
```

Equivalent to:

```yaml
filters:
  category:
    include:
      - match: news
        mode: auto
        split: true
    join: or
```

2. Scalar hash shortcut (`match` / `mode` / `split` / `first`)

```yaml
filters:
  name:
    match: cat
    mode: strict # strict | auto | only | first | firstN (default: auto)
    split: false # true|false|<non-empty delimiter string>
    first: 2 # only used by first/firstN modes, default 1
```

3. Range hash shortcut (`min` / `max`)

```yaml
filters:
  rating:
    min: 3
    max: 5
```

4. Delimited string shortcut

```yaml
filters:
  category: news,blog,updates
```

Equivalent to array shortcut with one scalar definition per split entry.

5. Array shortcut

```yaml
filters:
  category: [news, blog]
```

Equivalent to `include: [news, blog], join: or`.

### Scalar Hash Behaviour

- `match`: scalar definition to match (supports regex literal strings like `/^a/i`).
- `mode`:
  - `strict`: direct equality only.
  - `auto`: direct equality, or array includes.
  - `only`: like `auto`, but includes passes only when the array length is exactly `1`.
  - `first`: compare only against the first `N` entries in an array (`N` defaults to `1`).
  - `firstN`: same as `first`; use `first` to set `N`.
- `first`:
  - positive integer count used by `first`/`firstN`.
  - if omitted, defaults to `1`.
- `split`:
  - `true` (default): split compared string values using `pagination.split`.
  - `false`: do not split compared values.
  - non-empty string: override split delimiter for this scalar definition.

Splitting always trims and rejects blank elements.

### Range Behaviour

- `min` and/or `max` are supported (at least one required).
- Matching is inclusive (`>= min`, `<= max`).
- Numeric bounds are compared as floats when both ends are numeric.
- Date/time bounds support configured now keyword via `pagination.keywords.now`:
  - `now`
  - `now+1`, `now - 1`, `now + 0.5`
- If both bounds are present and `min > max`, they are swapped and a warning is logged.

### Matching and Key Resolution Notes

- Nested keys use `pagination.nested_key_separator` (`.` by default), e.g. `author.name`.
- Nested lookup traverses arrays at any path segment and collects all matching terminal values.
- Example: `links.products.category.name` over nested arrays resolves to a flat set like `[shoe, sandal, bag, leather]`.
- Equivalent keys in `pagination.equivalents` are respected during lookup.
- A synthetic `collection` key is also available for filtering by item collection label.
- Matching is path-wide, not branch-correlated across keys. Different filter keys can match values from different branches in the same item.
- Item values are normalised before matching:
  - arrays are flattened,
  - strings are not auto-split unless a scalar definition has `split` enabled,
  - empty values are removed.
- Invalid key definitions are ignored (that key is skipped). If `filters` itself is not a hash, no filtering is applied.

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

## Generated Templates (`pagination.templates.generate`)

Automatically generate pagination templates from frontmatter values:

```yaml
pagination:
  templates:
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
- `filter` is shorthand for applying the same per-key filter definition signature to each indexed key; if `filters.<key>` is explicitly set, that explicit key filter takes precedence.
- generated templates include `pagination.enabled: true` and are then expanded into indexes by the core generator.
- generated templates can be created as pages or collection docs via `location`.
- placeholders in generated `permalink`/`title` include each indexed key (for example `:owner.name`).

## Compatibility

Compatibility modes are migration helpers, not separate engines. The intended flow is:

1. existing site is on jekyll-paginate (v1) or jekyll-paginate-v2
2. install `jekyll-paginate-v3`
3. set `pagination.compatibility: v1` or `pagination.compatibility: v2`
4. existing pagination continues to work with little or no config rewrite, while you gradually adopt native v3 config and later remove compatibility mode

### `compatibility: v2`

- keeps v2-style paginator payload naming by default (`paginator.posts`),
- up-migrates legacy shortcut keys (`collection`, `category`, `tag`, `locale`),
- up-migrates old AutoPages config (`site.autopages`) into `pagination.templates.generate`.

### `compatibility: v1`

- reads `paginate` and `paginate_path` and up-migrates them into v3 config,
- keeps pagination on the standard v3 pipeline (templates, filters, sorting, trails, output model),
- defaults template discovery to `pagination.templates.location: pages`,
- if legacy `paginate` config is present and no explicit `pagination.enabled: true` template exists, automatically selects the legacy `index.html` hierarchy candidate as an implicit template.

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
- Templates are never included in their own paginated item sets.
- Generated indexes are marked with `page.pagination.generated: true` (and in `compatibility: v2` they also set `page.autogen: jekyll-paginate-v2`).


## Acknowledgements

This gem drew heavy inspiration from the [jekyll-paginate-v2](https://github.com/sverrirs/jekyll-paginate-v2) gem which itself was based on the original design of [jekyll-paginate](https://github.com/jekyll/jekyll-paginate).
