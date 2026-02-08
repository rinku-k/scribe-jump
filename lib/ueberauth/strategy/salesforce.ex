defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles initial request for Salesforce authentication.
  Salesforce requires PKCE (code_challenge) for the authorization code flow.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    # PKCE: generate code_verifier and code_challenge (Salesforce requires this)
    code_verifier = generate_code_verifier()
    code_challenge = code_challenge_from_verifier(code_verifier)

    conn =
      conn
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session("ueberauth_salesforce_code_verifier", code_verifier)

    opts =
      [scope: scopes, redirect_uri: callback_url(conn)]
      |> Keyword.put(:code_challenge, code_challenge)
      |> Keyword.put(:code_challenge_method, "S256")
      |> with_optional(:prompt, conn)
      |> with_param(:prompt, conn)
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Salesforce.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    code_verifier = Plug.Conn.get_session(conn, "ueberauth_salesforce_code_verifier")

    if is_nil(code_verifier) or code_verifier == "" do
      set_errors!(conn, [error("missing_code_verifier", "PKCE code_verifier missing. Try signing in again.")])
    else
      opts = [redirect_uri: callback_url(conn), code_verifier: code_verifier]

      case Ueberauth.Strategy.Salesforce.OAuth.get_access_token([code: code], opts) do
        {:ok, token} ->
          conn
          |> delete_code_verifier_from_session()
          |> fetch_user(token)

        {:error, {error_code, error_description}} ->
          set_errors!(conn, [error(error_code, error_description)])
      end
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection.
  """
  def handle_cleanup!(conn) do
    conn
    |> delete_code_verifier_from_session()
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    conn.private.salesforce_user["user_id"]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    %Credentials{
      expires: token.expires_at != nil,
      expires_at: token.expires_at,
      scopes: String.split(token.other_params["scope"] || "", " "),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type,
      other: %{instance_url: token.other_params["instance_url"]}
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["email"],
      name: user["name"],
      first_name: user["given_name"],
      last_name: user["family_name"],
      nickname: user["preferred_username"],
      image: user["picture"]
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)

    instance_url = token.other_params["instance_url"]

    case Ueberauth.Strategy.Salesforce.OAuth.get_user_info(token.access_token, instance_url) do
      {:ok, user} ->
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("user_info_error", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  # PKCE: 43–128 chars from [A-Za-z0-9-._~] (RFC 7636)
  defp generate_code_verifier do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  # code_challenge = base64url(sha256(code_verifier))
  defp code_challenge_from_verifier(verifier) do
    :sha256
    |> :crypto.hash(verifier)
    |> Base.url_encode64(padding: false)
  end

  defp delete_code_verifier_from_session(conn) do
    Plug.Conn.delete_session(conn, "ueberauth_salesforce_code_verifier")
  end
end
