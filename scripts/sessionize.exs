sourcefile = File.stream!("data/pageviews.csv", read_ahead: 100_000)
sinkfile = File.stream!("data/sessions.csv", [:delayed_write])
# A bad CSV writer
make_row = fn map -> Enum.join(map, ",") <> "\n" end

sourcefile
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
|> Stream.into(sinkfile)
|> Stream.run
