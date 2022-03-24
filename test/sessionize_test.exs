defmodule SessionizeTest do
  use ExUnit.Case
  doctest Sessionize

  setup do
    # replacing UUIDs with easy to discern names
    data =
      """
      apple,2020-01-01 00:02:00,pageview,/listing/b
      berry,2020-01-01 00:05:00,pageview,/listing/a
      candy,2020-01-01 00:06:00,pageview,/listing/b
      apple,2020-01-01 00:06:00,pageview,/listing/a
      apple,2020-01-01 00:08:00,pageview,/listing/a
      berry,2020-01-01 00:10:00,pageview,/listing/b
      """
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&Sessionize.parse/1)

    # `Sessionize.parse/1` transforms NaiveDateTimes to Gregorian seconds
    # but to make it easy to see differences in seconds I truncate them
    # the final three digits.
    state = %{
      # sessions are of the form [key, page_count, first_timestamp, last_timestamp]
      "apple" => ["apple", 2, 120, 360],
      "berry" => ["berry", 1, 300, 300],
      "candy" => ["candy", 2, 360, 360]
    }

    {:ok, %{data: data, state: state}}
  end

  describe "utility methods" do
    test "add pageview to held session", context do
      new = ["apple", 480, "pageview", "/listing/c"]

      expected =
        {[],
         %{
           "apple" => ["apple", 3, 120, 480],
           "berry" => ["berry", 1, 300, 300],
           "candy" => ["candy", 2, 360, 360]
         }}

      assert expected == Sessionize.split(new, context.state)
    end

    test "emits a session after time gap", context do
      new = ["berry", 605, "pageview", "/listing/c"]
      # we expect to emit the old session and begin a new one
      # with the most recent state.
      expected =
        {[["berry", 1, 300, 300]],
         %{
           "apple" => ["apple", 2, 120, 360],
           "berry" => ["berry", 1, 605, 605],
           "candy" => ["candy", 2, 360, 360]
         }}

      assert expected == Sessionize.split(new, context.state)
    end

    test "begins new session", context do
      new = ["dinner", 375, "pageview", "/listing/c"]

      expected =
        {[],
         %{
           "apple" => ["apple", 2, 120, 360],
           "berry" => ["berry", 1, 300, 300],
           "candy" => ["candy", 2, 360, 360],
           "dinner" => ["dinner", 1, 375, 375]
         }}

      assert expected == Sessionize.split(new, context.state)
    end

    test "one page starts a session in an empty accumulator" do
      new = ["berry", 100, "pageview", "blah"]
      expected = {[], %{"berry" => ["berry", 1, 100, 100]}}
      assert expected == Sessionize.split(new, %{})
    end
  end

  describe "using Flow" do
    test "the sum of session pageviews is the number of pageviews", context do
      session_pageviews =
        context.data
        |> Flow.from_enumerable()
        |> Flow.partition(key: &hd/1, stages: 1)
        # group sessions!
        |> Flow.emit_and_reduce(fn -> %{} end, &Sessionize.split/2)
        |> Flow.on_trigger(fn acc ->
          {Map.values(acc), %{}}
        end)
        |> Enum.map(fn [_, count, _, _] -> count end)
        |> Enum.sum()

      assert session_pageviews == Enum.count(context.data)
    end
  end
end
