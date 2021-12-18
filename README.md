# EctoSparkles

Some helpers to sparkle on top of [Ecto](https://hexdocs.pm/ecto/Ecto.html) to better filter queries, as well as join+preload associations.

- [`query_filter`](#query_filter-documentation)
- [`join_preload`](#join_preload-documentation)
- [`reusable_join`](#reusablejoin-documentation)

## `query_filter` Documentation

Helpers to make writing ecto queries more pleasant and the code shorter

### Usage

You can create queries from filter parameters, for example: 

```elixir
query_filter(User, %{id: 5})
```
is the same as:
```elixir
from u in User, where: id == 5
```

This allows for filters to be constructed from data such as:
```elixir
query_filter(User, %{
  favorite_food: "curry",
  age: %{gte: 18, lte: 50},
  name: %{ilike: "steven"},
  preload: [:address],
  last: 5
})
```
which would be equivalent to:
```elixir
from u in User,
  preload: [:address],
  limit: 5,
  where: u.favorite_food == "curry" and
         u.age >= 18 and u.age <= 50 and
         ilike(u.name, "%steven%")
```

You are also able to filter on any natural field of a schema, as well as use:
- gte/gt
- lte/lt
- like/ilike
- is_nil/not(is_nil)

For example:
```elixir
query_filter(User, %{name: %{ilike: "steve"}})
query_filter(User, %{name: "Steven", %{age: %{gte: 18, lte: 30}}})
query_filter(User, %{is_banned: %{!=: nil}})
query_filter(User, %{is_banned: %{==: nil}})

my_query = query_filter(User, %{first_name: "Daft"})
query_filter(my_query, %{last_name: "Punk"})
```

###### List of common filters
- `preload` - Preloads fields onto the query results
- `start_date` - Query for items inserted after this date
- `end_date` - Query for items inserted before this date
- `before` - Get items with IDs before this value
- `after` - Get items with IDs after this value
- `ids` - Get items with a list of ids
- `first` - Gets the first n items
- `last` - Gets the last n items
- `limit` - Gets the first n items
- `offset` - Offsets limit by n items
- `search` - ***Warning:*** This requires schemas using this to have a `&by_search(query, val)` function


## `join_preload` Documentation

A macro which tells Ecto to perform a join and preload of (up to 5 nested levels of) associations.

By default, Ecto preloads associations using a separate query for each association, which can degrade performance.

You could make it run faster by using a combination of join/preload, but that requires a bit of boilerplate (see examples below).

### Examples using just Ecto
```
  query
  |> join(:left, [o, activity: activity], assoc(:object), as: :object)
  |> preload([l, activity: activity, object: object], activity: {activity, [object: object]})
```

Ecto requires calling `Query.join/4`, `Query.assoc/3` and `Query.preload/2`. Here's another example:

```
  Invoice
  |> join(:left, [i], assoc(i, :customer), as: :customer)
  |> join(:left, [i], assoc(i, :lines), as: :lines)
  |> preload([lines: v, customers: c], lines: v, customer: c)
  |> Repo.all()
```

## Example using join_preload

With `join_preload`, you can accomplish this with just one line of code.

```
  query
  |> join_preload([:activity, :object])
```

```
  Invoice
  |> join_preload(:customer)
  |> join_preload(:lines)
  |> Repo.all()
```

As a bonus, `join_preload` automatically makes use of `reusable_join`
so calling it multiple times for the same association has no ill effects.


## `reusable_join` Documentation

A macro is similar to `Ecto.Query.join/{4,5}`, but can be called multiple times 
with the same alias.

Note that only the first join operation is performed, the subsequent ones that use the same alias
are just ignored. Also note that because of this behaviour, its mandatory to specify an alias when
using this function.

This is helpful when you need to perform a join while building queries one filter at a time,
because the same filter could be used multiple times or you could have multiple filters that
require the same join, which poses a problem with how the `filter/3` callback work, as you
need to return a dynamic with the filtering, which means that the join must have an alias,
and by default Ecto raises an error when you add multiple joins with the same alias.

To solve this, it is recommended to use this macro instead of the default `Ecto.Query.join/{4,5}`,
in which case there will be only one join in the query that can be reused by multiple filters.

### Creating reusable joins

```elixir
query
|> reusable_join(:left, [t1], t2 in "other_table", on: t1.id == t2.id, as: :other_a)
|> reusable_join(:left, [t1], t2 in "other_table", on: t1.id == t2.id, as: :other_b)
```


## Copyright 

- Copyright (c) 2021 Bonfire developers
- Copyright (c) 2020 Mika Kalathil
- Copyright (c) 2020 Up Learn
- Copyright (c) 2019 Joshua Nussbaum 

- `EctoSparkles.Filter` was originally forked from [EctoShorts](https://github.com/MikaAK/ecto_shorts), licensed under MIT)
- `join_preload` was originally forked from [Ecto.Preloader](https://github.com/joshnuss/ecto_preloader), licensed under WTFPL)
- `reusable_join` was originally forked from [QueryElf](https://gitlab.com/up-learn-uk/query-elf), licensed under Apache License Version 2.0
