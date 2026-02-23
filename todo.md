# V3

## Compatibility

We will maintain the possibility of compatibility with `jekyll-paginate-v2` and `jekyll-paginate`, by:

* v3 could be configured in such a way that it behaves similarly to v2 or v1 or could read their config (v3 is a more generalised superset)
* All of those configurations can be set in one go with the new config key `compatibility: v2`. This effectively merges over the defaults, one stage before any further user config merges over this again. In compatibility mode we also read legacy config keys and up-migrate them.
* Code that handles legacy support will be clearly marked out/commented so that it can potentially be removed easily in future.

The behaviour of v1 is documented at v1.md to help with compatibility planning. Similarly implement `compatibility: v1` which adjusts some of the config options and enables reading and up-migrating of old config entries.

### Disentangling v2.1 from 2.0

This codebase is actually already a fork of v2 with some added features, which we now need to graduate to being part of v3 or removed/altered. These are:

* Pagination pages can themselves be documents in collections, not just regular pages (original v2 only allowed normal pages).
* The whole `search` config parameter, allowing to configure where the Paginator will look for pagination pages.
* Source pagination page stays in its original location
* Allow `.` as a field splitter, not just `:`
* Some bugfixes
* Initial work (incomplete) on expanding pagination filters to allow filtering on any frontmatter key (see below). Current work may not be fully working or tested but gives an idea of the intended direction.

## Rename and Refactor

Much of the code still refers to PaginateV2 which is a module directly under `Jekyll`. Migrate so that the plugin lives under the namespace `Jekyll::Plugins::PaginateV3` under which there are modules to encapsulate different concerns, and to separate out code which functions as a type of Jekyll plugin, encapsulated in modules by plugin type, e.g. `Jekyll::Plugins::PaginateV3::Generators` or `Jekyll::Plugins::PaginateV3::Hooks`, etc. Despite this module naming, the code still lives under ./lib/jekyll-paginate-v3 i.e. do not move to ./lib/jekyll/plugins/paginate-v3/etc.

A core goal of V3 is a full-scale refactor of the codebase to upgrade it to our standards, in particular to ensure:
* DRYness throughout
* Readability of code for easy comprehension by other developers
* Maintainability and future extensibility
* Separation of concerns, encapsulation of logic into small units (no single file should be enormous)
* General best practices and ensuring the way the paginator works is elegant and efficient
* Robustness and error handling, especially given that we cannot guarantee how the end developer will (mis)configure their site, with helpful error output

## Search

Several config keys in different places in v3 will use the same format, that of a "search" for pagination pages. This "search" format can now be:

* `pages`, {collection_name}, `all` or `everything` as a direct string value, meaning search all pages, all docs in collection_name, or all docs in all collections, or all pages and all docs in all collections, respectively.
* hash: each key/val is type/path-filter(s), where "type" is one of the strings above, and path-filter(s) is a string or array of strings representing allowed filepaths. e.g. {posts: "*"}
* array: each element is either of the above. Array can be specified by a comma-delimited string.

This format is accepted as the value of `site.pagination.templates.location`, or in individual pagination templates at `page.pagination.items` or in `site.pagination.templates.generate[].items` (see below).

The strings `pages`, `all` and `everything` which are used to have special meaning can be changed with the config key `site.pagination.keywords` which can have a key for each such keyword to change, the value of which is the new keyword, e.g. `site.pagination.keywords.all: 'all-collections'`.

## Pagination

Currently pagination can filter on tags, categories and locales. We will expand this to allow **filtering on any arbitrary frontmatter value, including deeply nested values**.

In v3 filtering is accomplished by the `filters` config key, not `category`/etc. keys directly.

Further complete/enhance the filtering functionality so that nested keys can be used as the frontmatter key to filter on, separated by `.`. Note that `.` becomes the canonical only way to separate nested keys, however this separator is now configurable at `site.pagination.nested_key_separator` for which the alternative value `:` is accepted.

`collection`, `category`, `tag` and `locale` in `site.pagination` (defaults) and in overrides on an individual pagination page in the `pagination` key, are replaced entirely by `items` and `filters`. So an individual pagination page that paginates posts would have `pagination: items: posts`, and to limit it to posts with a certain category you'd add `filters: category: cats`. Using `collection`, `category`, `tag` and `locale` move to legacy support mode, where they are essentially shortcuts/alternatives to specifying/adding to `items` and `filters`, available if `compatibility: v2` is set.

Top level config can now also have `items` and `filters` to specify defaults (and can accept `collection`, `category`, `tag` and `locale` to set defaults in v2 mode).

### Templates and Indexes

In v3, a page/document with `pagination.enabled: true` is a pagination template. The paginator discovers templates and expands each one into index pages `1..n`.

## AutoPages

Currently autopages can generate pagination pages for each unique item of category, tag or collection. It works by first indexing all categories/tags in _posts and then generating a pagination page for each, which paginates over _posts with that category/tag. For collections, it creates a pagination page for each collection on the site, which paginates over that collection.

### Issues to fix

* Currently the collection autopaging iterates every doc in every collection, which is unnecessary. We only need to list the site collections and then create an autopage for each.
* Currently tag/category autopaging indexes tags/categories across all documents in any collection, but the resulting autopages don't set `collection: all` meaning the paginator will actually only look across _posts.

These issues may be resolved during the course of upgrading to include the following new features.

### New features

The AutoPage feature will be fully merged into the core functionality and not given a separate name. It is simply a way of creating templates with particular `items` and `filters` from config, by reading site files.

The `templates` config key is nested under `pagination`. This key is used for settings that apply to template discovery and generation. Automatically generating templates lives under `pagination.templates.generate`. In v2 mode, we additionally read `site.autopages` and up-migrate it to v3 by appending generated template definitions into `pagination.templates.generate`.

Again, categories, tags and collections will cease to have special treatment and become specific cases of a more general feature. We will now be able to **generate pagination pages based on any frontmatter key in any type of document/page**.

Instead of `categories`, `tags` and `collections` config, config now looks like:

```yaml
generate: # array of types of index to generate
- items: animals # animals collection. `items` has same format as in pagination i.e. is a type of search
  index: weight # frontmatter key to index, autopage will be generated for each unique value found
  #filters: # same format as paginator filters: only entries which match the filter are considered when building the index, and these filters will be applied to each such index page generated
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
  filter: /^s/
  # filter on multi-index is equivalent to applying that filter to each:
  filters:
    category: /^s/
    subcategory: /^s/
```

i.e. `generate` is an array of definitions of how to generate pagination templates. The old `categories`, `tags` and `collections` config keys will still be allowed and up-migrated in v2 mode, essentially making them alternatives/shortcuts into config like the above.

The `permalink` config key currently allows placeholders for `:coll`, `:cat` and `:tag`. In v3 the placeholder is automatically whatever frontmatter key you are indexing on, e.g. if you're indexing on `weight` then a `:weight` placeholder is available. Note that nested keys are possible like `owner.name` resulting in `:owner.name`. Watch out for possible clashes if `nested_key_separator` is changed to `:`; longest match wins. The `:coll`, `:cat` and `:tag` placeholders are available additionally as a special case (legacy support) if you indexed on `collection`, `category/ies` or `tag/s` and v2 mode is on.

For multi-level indexing, we index each of the frontmatter keys given in order, constructing a tree of key1/key2/key3 etc. For instance if we index on `category, subcategory`, then we might find docs with `category: shoes`. Among those we now index their `subcategory` in which we find `subcategory: sandals` and `subcategory: loafers`, thus we create two pagination pages, the first filtered on category=shoes and subcategory=sandals, and the second on category=shoes and subcategory=loafers. Both placeholders are now available in the permalink template.

The `layouts` config key for each generated index is now accepted as a string directly (doesn't have to be array) and now can also be specified by the alternative key `layout`. If both keys are used they are combined into one array.

Further new config:

```yaml
location: pages # where pagination templates are located; see above
generate:
- items: animals
  index: weight
  layout: html/index.html
  location: collection_name # override where these templates will be created (See below) 
  trail: 9 # etc. Can include any other config keys from pagination that should be overriden for this pagination page, e.g. trail, sort
  frontmatter:
    arbitrary: additional frontmatter
    that: will be added to generated pages
    note: clashes are overwritten by other frontmatter the generator writes
```

By default, generated templates are created in the same location where templates are expected to be found, as per `site.pagination.templates.location` (`pages` by default). If this config has multiple entries, the first is considered. If it is `pages` or `all`, templates are generated as pages; if it is a collection name, templates are generated as docs in that collection. This can be overridden with `location` in each `generate` entry, where valid values are `pages` or `{collection_name}`.

Note that a template can be generated into the same collection/set of items that it paginates. We always protect against including templates in pagination items.

## Equivalents

The frontmatter keys `tag` and `category` and their plurals have special treatment in v3, which is that they are always interchangeable with their pluralised forms, throughout the whole software. This behaviour of treating the singular/plural of these frontmatter keys as equivalent can be disabled via config `pagination.equivalents: false`. Equivalents defaults to `[[tag, tags], [category,categories]]` and could be used to make other alternative keys be treated as equivalents. Note that when both equivalent keys are found in frontmatter, the later-defined one takes precedence

## Paginator

On individual paginated pages (based on an index) the `page.paginator` variable is available. In v2 this exposes `paginator.posts` to access the items paginated to this page. In v3 this becomes `paginator.items`. However in global config we can set `pagination.keywords.items: posts` to set this back to `posts` (or other string) for backwards compatibility.

Likewise `total_posts` becomes `total_items` by default, but is `total_*` matching the keyword.

## Sorting

`sort_field` is uprgaded/changed in V3.

Rename to just `sort`.

`sort` can be a single string, comma-delimited array, or array. Each array element is `field` or `field [options]` e.g. `owner.name` or `owner.name desc empty:first`. Treating this as an argument string, the first param is the field to sort on, and other params are either `flag` or `named:value`.

Each array element defines a level of a multi-level sort.

Items are sorted on the given key (which could be a nested key), in ascending order by default (which could be made explicit by `asc` or `ascending` flag), or descending with the `desc` or `descending` flag. The `empty` named param is either `first` or `last` (default), i.e. elements for which the given field is missing or nil are sorted first/last.

A field cannot be relied on to have values that are all mutually comparable. If a field has mixed types, the ascending order is:
* TrueClass
* FalseClass
* Numeric
* String + anything else is stringified and sorted inamongst strings

For instance `sort: featured, date desc` would sort all items where `featured: true` first, followed by items with `featured` either missing or anything else. Then in each set, the items are sorted in date descending order.

Thus `sort_field` and `sort_reverse` are deprecated, but they will still be up-migrated to the above format.

## Note on comma-delimited arrays

Several fields in pagination configuration allow an array to be specified as a comma-delimited string. Wherever this is possible:

* That field could just be a single string (no commas)
* That field could be an actual array
* Each array item would then be string. Further commas at this point are not interpreted
* We strip each element of a comma-delimited array

## Readme

Readme is currently split across a main readme, and readmes for generator and autopages. Delete the additional readmes, and write a new readme that reflects all the features of v3 in one file. Ensure the readme is comprehensive and includes usage examples.
