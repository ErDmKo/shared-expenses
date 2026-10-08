defmodule SharedExpensesWeb.CoverController do
  use SharedExpensesWeb, :controller

  alias SharedExpenses.{Covers, Ledger}

  def show(conn, %{"slug" => slug}) do
    with %Ledger.Event{cover_filename: filename} when is_binary(filename) <-
           Ledger.get_event(slug),
         {:ok, path} <- Covers.path(filename),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(Covers.content_type(filename))
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Cover not found")
    end
  end
end
