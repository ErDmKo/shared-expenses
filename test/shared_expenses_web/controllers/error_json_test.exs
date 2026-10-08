defmodule SharedExpensesWeb.ErrorJSONTest do
  use SharedExpensesWeb.ConnCase, async: true

  test "renders 404" do
    assert SharedExpensesWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert SharedExpensesWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
