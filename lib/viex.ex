defmodule Viex do
  @temp_path System.tmp_dir!() <> "/ustids.txt"
  require Logger

  def generate_all_ids() do
    begin = 100000000
    Logger.configure(level: :warn)
    File.rm(@temp_path)
    File.touch(@temp_path)
    {:ok, file} = File.open(@temp_path, [{:delayed_write, 1_000_000, 10}])
    IO.inspect("Created file #{file |> inspect()}")
    numbers = generate_all_ids(begin, [])
    IO.inspect(numbers |> length)
    IO.inspect("generated numbers")

    Enum.reverse(numbers)
    |> Task.async_stream(
      fn number ->
        case valid?(Integer.to_string(number)) do
          true ->
            IO.write(file, "DE#{number}")
            Process.sleep(1_000)

          _ ->
            nil
        end
      end,
      max_concurrency: 100,
      timeout: 1000_000
    )
    |> Enum.filter(&(&1 != nil))
    |> Enum.each(&Logger.warn("Given #{&1 |> inspect()}"))

    File.close(file)
  end

  def generate_all_ids(999_999_999, numbers) do
    numbers
  end

  def generate_all_ids(number, numbers) when is_integer(number) do
    generate_all_ids(number + 1, [number + 1 | numbers])
  end

  @moduledoc """
  Look up and validate European VAT numbers.
  """

  @url "http://ec.europa.eu/taxation_customs/vies/services/checkVatService"

  @doc """
  Look up a European VAT number. Accepts a binary, returns a `Viex.Response` struct.
  Optionally accepts a `requester_vat` options that needs the VAT number of the entity
  the request is made on behalf of. It returns a `Viex.ApproxResponse` in that case
  """
  @spec lookup(String.t(), requester_vat: String.t() | nil) :: map | {:error, String.t()}
  def lookup(vat_number, opts \\ []) do
    requester_vat = Keyword.get(opts, :requester_vat)

    response =
      vat_number
      |> String.split_at(2)
      |> request(requester_vat)
      |> handle_soap_response

    case requester_vat do
      nil -> Viex.Response.parse(response)
      _ -> Viex.ApproxResponse.parse(response)
    end
  end

  @doc """
  Check the validity of a European VAT number. Accepts a binary, returns a boolean.
  """
  @spec valid?(String.t(), requester_vat: String.t() | nil) :: boolean
  def valid?(vat_number, opts \\ []) do
    vat_number
    |> lookup(opts)
    |> is_valid?
  end

  defp is_valid?(%Viex.ApproxResponse{valid: valid}), do: valid == true
  defp is_valid?(%Viex.Response{valid: valid}), do: valid == true
  defp is_valid?({:error, _reason}), do: false

  defp request({country, vat}, nil) do
    HTTPoison.post(@url, body(country, vat), headers(), params: params())
  end

  defp request({country, vat}, requester_vat) do
    {requester_country, requester_vat} = String.split_at(requester_vat, 2)

    HTTPoison.post(@url, body(country, vat, requester_country, requester_vat), headers(),
      params: params()
    )
  end

  defp handle_soap_response({:error, %HTTPoison.Error{reason: reason}}), do: {:error, reason}

  defp handle_soap_response({:ok, %HTTPoison.Response{status_code: 404}}),
    do: {:error, :not_found}

  defp handle_soap_response({:ok, %HTTPoison.Response{status_code: 500}}),
    do: {:error, :internal_server_error}

  defp handle_soap_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}),
    do: {:ok, body}

  defp headers do
    [
      {"SOAPAction", ""},
      {"Content-Type", "text/xml;charset=UTF-8"}
    ]
  end

  defp body(country, vat) do
    ~s(<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
        <soapenv:Header/>
        <soapenv:Body>
          <urn:checkVat>
            <urn:countryCode>#{country}</urn:countryCode>
            <urn:vatNumber>#{vat}</urn:vatNumber>
          </urn:checkVat>
        </soapenv:Body>
      </soapenv:Envelope>)
  end

  defp body(country, vat, requester_country, requester_vat) do
    ~s(<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
        <soapenv:Header/>
        <soapenv:Body>
          <urn:checkVatApprox>
            <urn:countryCode>#{country}</urn:countryCode>
            <urn:vatNumber>#{vat}</urn:vatNumber>
            <urn:requesterCountryCode>#{requester_country}</urn:requesterCountryCode>
            <urn:requesterVatNumber>#{requester_vat}</urn:requesterVatNumber>
          </urn:checkVatApprox>
        </soapenv:Body>
      </soapenv:Envelope>)
  end

  defp params, do: []
end
