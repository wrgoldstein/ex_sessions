# Motivation

A sandbox for learning the ins and outs of [Flow](https://github.com/dashbitco/flow), by taking a set of procedurally generated pageviews (in CSV form) and aggregating them into sessions separated by 5 minutes of inactivity.

Sessionizing in warehouse with SQL is typically a gross multi step process involving multiple passes over the data, so I was curious if a streamed sessionization with Flow might be more natural.

## Generating fake pageviews

I put almost no thought into the generation process and the resulting sessions are quite unrealistic- averaging 2 or 3 pages per session and the heaviest "user" only had 9 sessions over a period of months. But it gave us something to work with that doesn't have any privacy concerns.

You can tweak the script if you want more or less data.

```sh
python scripts/pagefaker.py > data/pageviews.csv
```

I could totally rewrite this in Elixir and express it more naturally and performantly (the current implementation takes several minutes to generate a few million pageviews). todo.

## Running flow

You can either run the test suite

```
mix test
```

or the `.exs` script to time a run for a larger dataset (assumes `data/pageviews.csv` has been populated by `scripts/pagefaker.py`):

```
time mix run scripts/sessionize.exs
```


## Performance

On my machine 1.6M pageviews could be sessionized in about 2.3 seconds, resulting in ~790k sessions.

150 million records would take 100x as long, about 3 minutes on my laptop. Pretty good! One thing to note is that it's critical to pass the `:delayed_write` option to `File.stream!/3`, as [described in the docs](https://hexdocs.pm/elixir/File.html#module-processes-and-raw-files):

>Every time a file is opened, Elixir spawns a new process. Writing to a file is equivalent to sending messages to the process that writes to the file descriptor.
>
>This means files can be passed between nodes and message passing guarantees they can write to the same file in a network.
>
>However, you may not always want to pay the price for this abstraction. In such cases, a file can be opened in :raw mode. The options :read_ahead and :delayed_write are also useful when operating on large files or working with files in tight loops.

Not doing so results in about a 10x speed penalty as Elixir opens a new process for each write.

There's lots that could be done to make this better and more Elixiry, like using a struct to hold the session info, but the intent is just to show custom window functions using `emit_and_reduce/2` and `on_trigger/1`.

## Impressions

Flow is cool! I struggled a bit to represent the sessionization logic (see `lib/sessionize.ex`). I'm sure there are better ways to do so, but I got to "it works" and left it alone, for now.

The interplay between `emit_and_reduce/2` and `on_trigger/1` is obvious to me now, but I spent a bunch of time trying to understand the output of my Flow pipeline. The [Flow.Window](https://hexdocs.pm/flow/Flow.Window.html) documentation mentions session windows, but this was [removed in the 2018 0.14 release](https://github.com/dashbitco/flow/blob/master/CHANGELOG.md#v0140-2018-06-10), which says:

>This release also deprecates Flow.Window.session/3 as developers can trivially roll their own with more customization power and flexibility using emit_and_reduce/3 and on_trigger/2.

I would say it's only somewhat trivial, but I do love the flexibility.

## Explanation

```elixir
# A bad CSV writer
make_row = fn list -> Enum.join(list, ",") <> "\n" end

# A sessionizing flow
File.stream!("data/out.csv")
|> Flow.from_enumerable()
|> Flow.map(&Sessionize.parse/1)  # take the raw string data and make lists
|> Flow.partition(key: &hd/1)  # routes rows to different stages based on the UUID
|> Flow.emit_and_reduce(fn -> %{} end, fn row, acc ->
  {emit, state} = Sessionize.split(row, acc) # the workhorse, more later
  
  # `emit` is sessions that have been marked as finished by the presence of events more 
  # than 5 minutes after the last event in the session.

  # `state` is the accumulator of sessions that have not yet been closed out This becomes 
  # `acc` in the next fold of the reducer
  {Enum.map(emit, make_row), state}
end)
|> Flow.on_trigger(fn acc ->
  # When the stages close down (because File.stream! has indicated there are no more events),
  # a :done trigger is sent. At this point the remaining accumulator for each stage is passed
  # to `on_trigger/1`, which gives us an opportunity to close them out as finished sessions.

  # If you expected this process to pick up where it left off, these triggered sessions might
  # not actually be complete, so one might want to store them separately so they can be the
  # initial state of the reducer and the process can resume.
  {Map.values(acc) |> Enum.map(make_row), %{}}
end)
|> Stream.into(sinkfile)
|> Stream.run
```

When it comes to managing state, we take a new row and ask if its timestamp indicates that any of the sessions we are holding are finished. We emit any finished sessions, and then either update the session associated with the new row or start a new one.

There's lots that could go wrong with late arriving events in this setup, but for a first pass its reasonably clean and easy to understand.

## In the future

I'd like to clean up this code (the sessionization must be expressible in a simpler way), find an example that needs window joins, and see what throughput characteristics you get with cloud storage / a warehouse. I also want to play with Genstage, particularly with a multi machine distributed workload.
