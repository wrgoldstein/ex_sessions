defmodule Sessionize do
  @moduledoc """
  Experimental code for creating a session window in Flow.

  Events more than 5 minutes late will start new sessions, even
  if by event time they should be in the previous session.
  """

  # 5 minutes
  @session_cutoff 5 * 60

  def split([key, time, _, _], state) when state == %{} do
    {[], %{key => [key, 1, time, time]}}
  end

  def split(current, state) do
    [event_key, event_time, _, _] = current

    Enum.reduce(state, {[], state}, fn {_key, session}, {sessions, state} ->
      unless Map.has_key?(state, event_key) do
        state = Map.put(state, event_key, [event_key, 1, event_time, event_time])
        resolve_state(event_key, event_time, session, sessions, state)
      else
        resolve_state(event_key, event_time, session, sessions, state)
      end
    end)
  end

  def resolve_state(key, event_time, [key, _count, _, max_t] = session, sessions, state) do
    if event_time - max_t > @session_cutoff do
      {[session | sessions],
       Map.put(
         state,
         key,
         [key, 1, event_time, event_time]
       )}
    else
      {sessions,
       Map.update(
         state,
         key,
         [key, 1, event_time, event_time],
         fn [_, count, min_t, _] -> [key, count + 1, min_t, event_time] end
       )}
    end
  end

  def resolve_state(_key, event_time, [inner_key, _count, _, max_t] = session, sessions, state) do
    if event_time - max_t > @session_cutoff do
      {[session | sessions], Map.delete(state, inner_key)}
    else
      {sessions, state}
    end
  end

  def date_to_seconds(date) do
    {secs, _} =
      date
      |> NaiveDateTime.from_iso8601!()
      |> NaiveDateTime.to_gregorian_seconds()

    secs
  end

  def parse(row) do
    [key, ts, event, path] = String.split(row, ",")
    [key, date_to_seconds(ts), event, path]
  end
end
