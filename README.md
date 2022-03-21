# Motivation

A sandbox for learning the ins and outs of [Flow](https://github.com/dashbitco/flow), by taking a set of procedurally generated pageviews (in CSV form) and aggregating them into sessions separated by 5 minutes of inactivity.

Sessionizing in warehouse with SQL is typically a gross multi step process involving multiple passes over the data, so I was curious if a streamed sessionization with Flow might be more natural.

## Generating fake pageviews

I put almost no thought into the generation process and the resulting sessions are quite unrealistic- averaging 2 or 3 pages per session and the heaviest "user" only had 9 sessions over a period of months. But it gave us something to work with that doesn't have any privacy concerns.

You can tweak the script if you want more or less data.

```python
python pagefaker.py > out.csv
```

## Running flow

You can either run the test suite

```
mix test
```

or the `.exs` script, which is easier to tweak and observe:

```
mix run sessionize.exs
```


## Performance

On my machine sessionizing 1.6M pageviews could be sessionized and counted in ~2 seconds. Serializing these to a CSV file took about 20 seconds, so IO is clearly a bottleneck.

150 million records would take 100x as long, about half an hour on my laptop. If you parallelized IO with the right batch size you'd likely just be bound by your internet connection-- an EC2 instance writing to S3 should be super speedy, I'd love to test this.

There's lots that could be done to make this better and more Elixiry, like using a struct to hold the session info, but the intent is just to show custom window functions using `emit_and_reduce/2` and `on_trigger/1`.

## Impressions

Flow is cool! I struggled a bit to represent the sessionization logic (see `lib/sessionize.ex`). I'm sure there are better ways to do so, but I got to "it works" and left it alone, for now.

The interplay between `emit_and_reduce/2` and `on_trigger/1` is obvious to me now, but I spent a bunch of time trying to understand the output of my Flow pipeline. I think the official elixir docs could explain this more clearly for a beginner.

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
