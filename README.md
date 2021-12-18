# Ecto Sparkles

Some helpers to sparkle on top of [Ecto](https://hexdocs.pm/ecto/Ecto.html) to better join + preload associations.

- [`join_preload`](#join_preload-documentation)
- [`reusable_join`](#reusablejoin-documentation)


## join_preload Documentation

The `join_preload` macro tells Ecto to perform a join and preload of (up to 5 nested levels of) associations.

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


## reusable_join Documentation

The `reusable_join` macro is similar to `Ecto.Query.join/{4,5}`, but can be called multiple times 
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
- Copyright (c) 2020 Up Learn
- Copyright (c) 2019 Joshua Nussbaum 

- `join_preload` was orginally forked from [Ecto.Preloader](https://github.com/joshnuss/ecto_preloader), licensed under WTFPL)
- `reusable_join` was originally forked from [QueryElf](https://gitlab.com/up-learn-uk/query-elf), licensed under Apache License Version 2.0
