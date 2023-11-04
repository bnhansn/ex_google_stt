defmodule GCloud.SpeechAPI.Streaming.ClientTest do
  use ExUnit.Case, async: true

  alias Google.Cloud.Speech.V1.{
    RecognitionConfig,
    SpeechRecognitionAlternative,
    StreamingRecognitionConfig,
    StreamingRecognitionResult,
    StreamingRecognizeRequest,
    StreamingRecognizeResponse
  }

  alias GCloud.SpeechAPI.Streaming.Client, as: StreamingClient

  @recognition_cfg %RecognitionConfig{
    audio_channel_count: 1,
    encoding: :FLAC,
    language_code: "en-GB",
    sample_rate_hertz: 16_000
  }

  @sound_fixture_path "../../fixtures/sample.flac" |> Path.expand(__DIR__)

  @tag :external
  test "recognize in parts" do
    cfg = %RecognitionConfig{
      audio_channel_count: 1,
      encoding: :FLAC,
      language_code: "en-GB",
      sample_rate_hertz: 16_000
    }

    str_cfg = %StreamingRecognitionConfig{config: cfg, interim_results: false}

    str_cfg_req = %StreamingRecognizeRequest{streaming_request: {:streaming_config, str_cfg}}

    <<part_a::binary-size(48_277), part_b::binary-size(44_177), part_c::binary>> =
      File.read!(@sound_fixture_path)

    content_reqs =
      [part_a, part_b, part_c]
      |> Enum.map(fn data ->
        %StreamingRecognizeRequest{streaming_request: {:audio_content, data}}
      end)

    assert {:ok, client} = StreamingClient.start_link()
    client |> StreamingClient.send_request(str_cfg_req)

    content_reqs
    |> Enum.each(fn stream_audio_req ->
      StreamingClient.send_request(
        client,
        stream_audio_req
      )
    end)

    StreamingClient.end_stream(client)

    assert_receive %StreamingRecognizeResponse{results: results}, 5000
    assert [%StreamingRecognitionResult{alternatives: alternative}] = results
    assert [%SpeechRecognitionAlternative{transcript: transcript}] = alternative

    assert transcript ==
             "Adventure one a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"
  end

  @tag :external
  test "recognize in one request and include sender" do
    str_cfg = %StreamingRecognitionConfig{config: @recognition_cfg, interim_results: false}
    str_cfg_req = %StreamingRecognizeRequest{streaming_request: {:streaming_config, str_cfg}}

    data = File.read!(@sound_fixture_path)
    stream_audio_req = %StreamingRecognizeRequest{streaming_request: {:audio_content, data}}

    assert {:ok, client} = StreamingClient.start_link(include_sender: true)
    client |> StreamingClient.send_request(str_cfg_req)

    StreamingClient.send_request(
      client,
      stream_audio_req
    )

    StreamingClient.end_stream(client)

    assert_receive {^client, %StreamingRecognizeResponse{results: results}}, 5000
    assert [%StreamingRecognitionResult{alternatives: alternative}] = results
    assert [%SpeechRecognitionAlternative{transcript: transcript}] = alternative

    assert transcript ==
             "Adventure one a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"
  end

  test "shoutdown on monitored process down" do
    target = self()

    task =
      Task.async(fn ->
        send(target, {:client, StreamingClient.start(monitor_target: true)})
        receive do: (:exit -> :ok)
      end)

    assert_receive {:client, {:ok, client}}, 2000
    ref = Process.monitor(client)
    send(task.pid, :exit)
    assert :ok = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^client, :normal}
  end
end
