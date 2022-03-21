sourcefile = File.stream!("data/out.csv")
sinkfile = File.stream!("data/out2.csv")

# A bad CSV writer
make_row = fn map -> Enum.join(map, ",") <> "\n" end

sourcefile
|> Stream.take(800_000)
|> Flow.from_enumerable()
|> Flow.map(&Sessionize.parse/1)
|> Flow.partition(key: &hd/1, stages: 100)
|> Flow.emit_and_reduce(fn -> %{} end, fn row, acc ->
  {emit, state} = Sessionize.split(row, acc)
  {Enum.map(emit, make_row), state}
end)
|> Flow.on_trigger(fn acc ->
  {Map.values(acc) |> Enum.map(make_row), %{}}
end)
|> Stream.into(sinkfile)  # No way to parallelize disk writes
|> Stream.run
# |> Enum.count  # counting is 10x faster than writing to disk
# |> IO.inspect
