# jekyll-paginate-v2: Codebase Operation Summary (lib/)

## Top-level overview

This plugin wires into Jekyll as a `Generator` and does two major jobs during a build:

1. Auto-generate pagination template pages for tags, categories, and collections (`AutoPages` subsystem).
2. Convert pagination-enabled template pages into concrete paginated output pages (`Generator` subsystem).

The entry point is `lib/jekyll-paginate-v2.rb`, which requires all generator and autopage classes and constants.

## Runtime lifecycle during a Jekyll build

`Jekyll::PaginateV2::Generator::PaginationGenerator#generate(site)` is the main execution path.

Build order:

1. `AutoPages.create_autopages(site)` runs first and may inject new in-memory pages into `site.pages`.
2. Site-level pagination config is merged with defaults.
3. Legacy `paginate` config is mapped into v2 config (deprecated compatibility path).
4. If pagination is enabled, generator discovers candidate template pages/docs to paginate.
5. `PaginationModel` is instantiated with lambdas that abstract Jekyll-specific operations:
   - add page/doc
   - remove page/doc
   - resolve collection docs by name
   - log messages
6. `PaginationModel#run` processes each template and emits paginated pages.

## Configuration model and precedence

There are two default config constants:

- Pagination defaults: `PaginateV2::Generator::DEFAULT`
- AutoPages defaults: `PaginateV2::AutoPages::DEFAULT`

Merge order (later wins):

1. hard-coded defaults
2. site `_config.yml` (`pagination` / `autopages`)
3. per-template front matter (`page.data['pagination']`)
4. for AutoPages, layout front matter overrides are merged into autopage/pagination config in `BaseAutoPage`

Deprecation handling in model:

- `title_suffix` is migrated to `title` if needed.
- top-level `category`, `tag`, `locale` are migrated into `filters`.

## Generator subsystem (pagination proper)

### `paginationGenerator.rb`

Responsibilities:

- Jekyll hook implementation (`safe true`, `priority :lowest`).
- Optional legacy config bridging from old `jekyll-paginate`.
- Template discovery scope configuration via `pagination.search`.
- Search path wildcard handling and filtering for:
  - `pages`
  - specific collections
  - collection catch-alls (`all`, `collections`)
- Creates and passes lambdas into `PaginationModel`:
  - `collection_by_name_lambda`
  - `page_add_lambda`
  - `page_remove_lambda`
  - `logging_lambda`

Important behaviour:

- Excludes docs with a `pagination` key from source content collections when building paginated lists.
- In `collection: all`, it intentionally excludes `posts`.

### `paginationModel.rb`

Core orchestration:

1. Finds pagination templates (`pagination.enabled: true`) from discovered pages/docs.
2. Merges config and applies deprecation transforms.
3. Loads source docs across requested collection(s).
4. Filters docs using `config['filters']`.
5. Sorts docs by configured field.
6. Applies offset, reverse, and page limit.
7. Removes original template from site collection.
8. Creates new in-memory paginated pages (`PaginationPage` or `PaginationDoc`).
9. Assigns pager object (`Paginator`) per generated page.
10. Optionally builds pagination trail objects (`PageTrail`).

### `paginationPage.rb`

Contains two in-memory page types used for generated output:

- `PaginationPage < Jekyll::Page` for normal pages.
- `PaginationDoc < Jekyll::Document` for collection docs.

Shared behaviour:

- Copy template data/content.
- Set `pagination_info` (`curr_page`, `total_pages`).
- Preserve extension behaviour for proper output classification.
- Copy `autopage` metadata into `autopages` when source is an AutoPage-derived template.
- Expose `set_url` to override URL after pager calculation.

### `paginator.rb`

`Paginator` is the data object exposed to Liquid via `to_liquid`.

Provides:

- current page, total pages, per-page counts
- current slice of posts/docs
- previous/next page numbers and paths
- first/last page numbers and paths
- optional `page_trail`

`PageTrail` is a small object (`num`, `path`, `title`) used for numbered trail rendering.

### `utils.rb` (generator)

General helpers:

- page count calculation
- macro replacement (`:num`, `:max`, `:title`)
- path normalisation (`leading/trailing slash`, `leading dot`)
- full path enforcement with index/ext
- sort comparison and nested field extraction (`sort_field` supports `:` or `.` hierarchy)

### `compatibilityUtils.rb`

Legacy helpers for old `jekyll-paginate` semantics:

- locate legacy template page
- compute legacy pagination path
- generate compatibility pages (`CompatibilityPaginationPage`)

This path is still present but time-gated by a hard expiry check in `run_compatability`.

## AutoPages subsystem

### `autoPages.rb`

Runs before main pagination generation.

Flow:

1. Merge autopage and pagination configs.
2. If enabled, collect all docs from all collections (`collect_all_docs`).
3. Build index values for tags, categories, and collection labels.
4. For each index value and each configured layout, create a page:
   - `TagAutoPage`
   - `CategoryAutoPage`
   - `CollectionAutoPage`
5. Push pages into `site.pages`.

### `pages/baseAutoPage.rb`

Base constructor logic for all autopage types:

- Reads `_layouts/<layout_name>` as template source.
- Merges config overrides from layout front matter.
- Injects a filter into pagination config (`tag`, `category`, or `collection`) via lambda.
- Expands permalink/title macros.
- Sets:
  - `data['permalink']`
  - `@url`
  - `@dir`
  - `data['layout']`
  - `data['title']`
  - `data['pagination']`
  - `data['autopage']` metadata

### `pages/tagAutoPage.rb`, `categoryAutoPage.rb`, `collectionAutoPage.rb`

Thin wrappers that define lambdas for:

- setting pagination filter key
- formatting permalink/title macros:
  - `:tag`
  - `:cat`
  - `:coll`

Each supports slugification options (`mode`, `cased`).

### `autopages/utils.rb`

Helpers for:

- macro formatting with slugify
- collecting docs from collections and tagging each with `__coll`
- indexing metadata values while preserving display names

## Data shape available to templates

Generated paginated pages expose:

- `page.pagination_info.curr_page`
- `page.pagination_info.total_pages`
- `paginator` object with keys from `Paginator#to_liquid`, including:
  - `posts`
  - `page`, `total_pages`
  - `previous_page_path`, `next_page_path`
  - `first_page_path`, `last_page_path`
  - `page_trail` (array of `{num, path, title}`)

AutoPages additionally expose:

- `page.autopage` metadata (layout path and display name)
- copied autopage info in generated pagination pages under `page.autopages` for convenience

## Notable behavioural details and current risk areas

Observed directly in current `lib/` implementation:

- `AutoPages` always runs before pagination template expansion.
- Pagination template discovery is path-scoped and supports wildcard matching.
- Hidden docs (`hidden: true`) are removed before pagination.
- Offset currently uses `using_posts.pop(offset)` after sorting, which removes from the end, not the beginning.
- `combine` is read but not used.
- `PaginationIndexer` contains several implementation defects/inconsistencies:
  - mixed class/instance method usage in filter normalisation/checking
  - recursion call signature mismatch in `check_filter`
  - several malformed/typo-prone lines in filter normalisation
- Some syntax forms (for example `is_a? Hash`) are legacy-style and raise syntax errors on newer Ruby parsers; this code is likely tied to older Ruby versions.
- There are multiple unconditional `puts` debug prints in pagination execution paths.

## Practical extension points for future feature work

Most useful places to extend safely:

- `paginationGenerator.rb`: search/discovery rules and site integration hooks.
- `paginationModel.rb`: pagination pipeline, filtering/sorting/paging semantics.
- `paginator.rb`: Liquid contract fields and link/path generation.
- `autopages/baseAutoPage.rb`: autopage metadata contract and layout-driven overrides.
- `generator/utils.rb`: canonical path/title/page-number formatting and sort extraction.

For new features, keep behaviour centralised in `PaginationModel` and helpers to avoid duplicating logic between Page/Document and AutoPages code paths.
