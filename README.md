# Serverboards.MOM

Elixir MOM is a Message Oritented Middleware for Elixir.

A Message Oriented Middleware is a middleware base don channels and tools around
it.

## Installation

The package can be installed as:

  1. Add mom to your list of dependencies in `mix.exs`:

        def deps do
          [{:mom,  git: "git://github.com/serverboards/elixir-mom"}]
        end

  2. Ensure mom is started before your application:

        def application do
          [applications: [:mom]]
        end

It will be added to [hex.pm](https://hex.pm) soon.

# Rationale

Although Elixir provides many tools to create channels and similar behaviours as
[GenEvent](http://elixir-lang.org/docs/stable/elixir/GenEvent.html), they were
not perfectly fit for our use at Serverboards.

  * We needed it function based (not behaviour / module+function based),
  * different kinds of channels: broadcast, point to point, named
  * JSON-RPC ready implementation

It should be possible to construct all we needed on top of vanilla GenEvent, but
it would not fit as well in the MOM paradigm as current Elixir MOM does.
