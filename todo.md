# V3

## Compatibility

We will maintain the possibility of compatibility with `jekyll-paginate-v2` and `jekyll-paginate`, by:

* If we find config from v1 or v2 which can be up-interpreted into v3 without a clash, we will gracefully do so.
* v3 could be configured in such a way that it behaves similarly to v2 or v1 or could read their config (v3 is a more generalised superset)

The compatibility behaviour of v1 is documented at v1.md.

### Disentangling v2.1 from 2.0

This codebase is actually already a fork of v2 with some added features, which we now need to graduate to being part of v3. These are:

* Pagination pages can themselves be documents in collections, not just regular pages (original v2 only allowed normal pages).
* The whole `search` config parameter, allowing to configure where the Paginator will look for pagination pages.
* Source pagination page stays in its original location
* Allow `.` as a field splitter, not just `:`
* Some bugfixes
* Initial work (incomplete) on expanding pagination filters to allow filtering on any frontmatter key (see below). Current work may not be fully working or tested but gives an idea of the intended direction.

## Search

Several config keys in different places in v3 will use the same format of a "search". This can now be:

* `pages`, collection_name or `all` as a direct string value, meaning search all pages, all doc in that collection, or all docs in all collections, respectively.
* hash: each key/val is type/path-filter(s), where "type" is one of the strings above, and path-filter(s) is a string or array of strings representing allowed filepaths
* array: each element is either of the above.

This format is accepted as the value of `site.pagination.search`, or in individual pagination pages at `page.pagination.items` or in `site.pagination.autoindex.generate[].items` (see below).

## Pagination

Currently pagination can filter on tags, categories and locales. We will expand this to allow pagination on any arbitrary frontmatter value, including deeply nested values.

In v3 filtering is accomplished by the `filters` config key, not `category`/etc. keys directly.

Further complete/enhance the filtering functionality so that nested keys can be used as the frontmatter key to filter on, separated by `.`. Note that `.` becomes the canonical only way to separate nested keys, doing away with `:` from v2 unless v2 mode is on.

`collection`, `category`, `tag` and `locale` in `site.pagination` (defaults) and in overrides on an individual pagination page in the `pagination` key, are replaced entirely by `items` and `filters`. So an individual pagination page that paginates posts would have `pagination: items: posts`, and to limit it to posts with a certain category you'd add `filters: category: cats`. Using `collection`, `category`, `tag` and `locale` move to legacy support mode, where they are essentially shortcuts/alternatives to specifying/adding to `items` and `filters`.

Top level config can now also have `items` and `filters` to specify defaults.

### Indexes

In v3 we will use the term "index" to refer to what in v2 is called a "pagination page". That is, any page where the paginator is active, i.e. where we will list some set of items potentially over multiple pages, is an "index" or "index page".

## AutoPages

Currently autopages can generate pagination pages for each unique item of category, tag or collection. It works by first indexing all categories/tags in _posts and then generating a pagination page for each, which paginates over _posts with that category/tag. For collections, it creates a pagination page for each collection on the site, which paginates over that collection.

### Issues to fix

* Currently the collection autopaging iterates every doc in every collection, which is unnecessary. We only need to list the site collections and then create an autopage for each.
* Currently tag/category autopaging indexes tags/categories across all documents in any collection, but the resulting autopages don't set `collection: all` meaning the paginator will actually only look across _posts. We will change the default behaviour of the autopage indexer to only index tags/categories on _posts.

### New features

The AutoPage feature will be fully merged into the core functionality and not given a separate name. It is simply a way of creating indexes with particular `items` and `filters` from config by reading site files.

The `indexes` config key will now be nested under the `pagination` key rather than as a top-level key at `site.indexes`. This key will also be used only for other settings that apply to all indexes. The part that corresponds to automatically generating indexes will live under `pagination.indexes.generate`. If the value here is the exact string "autopages" then this engaged compatibility mode in which we read the old config value at `site.autopages` and try to up-migrate it to v3.

Again, categories, tags and collections will cease to have special treatment and become specific cases of a more general feature. We will now be able to generate pagination pages based on any frontmatter key in any type of document/page.

Instead of `categories`, `tags` and `collections` config, config now looks like:

```yaml
generate: # array of types of index to generate
- items: animals # animals collection. items has same format as in pagination
  index: weight # frontmatter key to index, autopage will be generated for each unique value found
  #filters: # same format as paginator filters: only entries which match the filter are considered when building the index
- items: posts
  index: tag # see new feature below about equivalents
  filter: blog, news # `filter` (singular) key equivalent to a `filters` entry for the indexed frontmatter keys, i.e. this is equivalent to:
  filters:
    tag: blog, news
  # the `filter` shortcut just adds an entry to implicit `filters`
- items: all
  index: collection
  # this is equivalent to current `collection` behaviour
- items: products
  index: category, subcategory # multi-level index, see below
```

i.e. `generate` is an array of definitions of how to generate index pages. The old `categories`, `tags` and `collections` config keys will still be allowed and up-migrated, essentially making them alternatives/shortcuts into config like the above.

The `permalink` config key currently allows placeholders for `:coll`, `:cat` and `:tag`. In v3 the placeholder is automatically whatever frontmatter key you are indexing on, e.g. if you're indexing on `weight` then a `:weight` placeholder is available. Note that nested keys are possible like `owner.name` resulting in `:owner.name`, however in v2 mode `owner:name` would be allowed to specify the nested key but the placeholder would remain `:owner.name`. The `:coll`, `:cat` and `:tag` placeholders are available additionally as a special case if you indexed on `collection`, `category/ies` or `tag/s`.

For multi-level indexing, we index each of the frontmatter keys given in order, constructing a tree of key1/key2/key3 etc. For instance if we index on `category, subcategory`, then we might find docs with `category: shoes`. Among those we now index their `subcategory` in which we find `subcategory: sandals` and `subcategory: loafers`, thus we create two pagination pages, the first filtered on category=shoes and subcategory=sandals, and the second on category=shoes and subcategory=loafers. Both placeholders are now available in the permalink template.

The `layouts` config key for each autoindex is now accepted as a string directly (doesn't have to be array) and now can also be specified by the key `layout`.

Note additional new config:

```yaml
generate:
- items: animals
  index: weight
  layout: html/index.html
  collection: index # each generated page will be created as a doc in this collection; if not specified the default is to create as a page
  # any other config keys from pagination that should be overriden for this pagination page, e.g. trail, sort_field
  frontmatter:
    arbitrary: additional frontmatter
    that: will be added to generated pages
    note: clashes are overwritten by other frontmatter the generator writes
```

## Equivalents

The frontmatter keys `tag` and `category` and their plurals have special treatment in v3, which is that they are always interchangeable with their pluralised forms, throughout the whole software. This behaviour of treating the singular/plural of these frontmatter keys as equivalent can be disabled via config `pagination.equivalents: false`. Equivalents defaults to `[[tag, tags], [category,categories]]` and could be used to make other alternative keys be treated as equivalents. Note that when both equivalent keys are found in frontmatter, the later-defined one takes precedence

## Paginator

On individual paginated pages (based on an index) the `page.paginator` variable is available. In v2 this exposes `paginator.posts` to access the items paginated to this page. In v3 this becomes `paginator.items`. However in global config we can set `pagination.paginator.items: posts` to set this back to `posts` (or other string) for backwards compatibility.

Likewise `total_posts` becomes `total_items` by default, but is `total_*` matching the config value.