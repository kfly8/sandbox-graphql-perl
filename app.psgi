use v5.36;
use utf8;

use Plack::Builder;
use HTTP::Entity::Parser;
use Hash::MultiValue;
use Encode;
use Cpanel::JSON::XS;

use Data::Section::Simple qw(get_data_section);

use DBIx::Sunny;
use GraphQL::Schema ();
use GraphQL::Language::Parser ();
use GraphQL::Execution ();
use GraphQL::Type::Object;

my $schema = GraphQL::Schema->from_doc(<<SCHEMA);
  type Query {

      """エントリー一覧"""
      entries: [Entry!]
  }

  type Entry {
      """ID"""
      id: ID!

      """Entryのタイトル"""
      title: String!

      """Entryの本文"""
      body: String!

      """Entryへのコメント"""
      comments: [EntryComment!]
  }

  type EntryComment {
     id: ID!

     """コメント本文"""
     body: String!
  }
SCHEMA

my $resolvers = {
    Query => {
        entries => sub {
            my $dbh = connect_db();
            my $entries = $dbh->select_all('SELECT id, title, body FROM entry');
            return $entries;
        },
    },
};


sub connect_db {
    my $user     = $ENV{BLOG_SQLITE_USER}     || '';
    my $password = $ENV{BLOG_SQLITE_PASSWORD} || '';
    my $dbname   = $ENV{BLOG_SQLITE_NAME}     || 'blog.db';

    my $dsn = "dbi:SQLite:database=$dbname";
    my $dbh = DBIx::Sunny->connect($dsn, $user, $password, {});
    return $dbh;
}

my $json_encoder = Cpanel::JSON::XS->new->utf8;

my $body_parser = HTTP::Entity::Parser->new();
$body_parser->register(
    'application/json',
    'HTTP::Entity::Parser::JSON'
);

sub parse_body_parameters {
    my $env = shift;

    my ($body_parameters) = $body_parser->parse($env);
    return Hash::MultiValue->new(map { Encode::decode_utf8($_) } @{$body_parameters})
}

sub graphiql {
    my $html = get_data_section('graphiql.html');

    return [
        200,
        [
            'Content-Type' => 'text/html; charset=utf-8',
            'Content-Length' => length $html,
        ],
        [ $html ]
    ];
};

sub graphql {
    my $env = shift;

    return not_found($env) unless $env->{REQUEST_METHOD} eq 'POST';

    my $body_parameters = parse_body_parameters($env);

    my $query = $body_parameters->{query};
    my $variables = $body_parameters->{variables};
    my $operation_name = $body_parameters->{operationName};

    my $parsed_query = GraphQL::Language::Parser::parse($query);

    # XXX Query 決め打ち
    my $root_value = $resolvers->{Query};

    my $context = { };

    my $result = GraphQL::Execution::execute(
        $schema,
        $parsed_query,
        $root_value,
        $context,
        $variables,
        $operation_name,
    );

    my $json = $json_encoder->encode($result);

    return [
        200,
        [
            'Content-Type' => 'application/json; charset=utf-8',
            'Content-Length' => length $json,
        ],
        [$json]
    ]
};

sub not_found {
    return [
        404,
        ['Content-Type' => 'text/plain'],
        ['Not Found']
    ];
};

builder {
    mount '/graphql' => builder {
        enable 'CrossOrigin', origins => '*';
        \&graphql;
    };
    mount '/graphiql' => \&graphiql;
    mount '/' => \&not_found;
};

__DATA__

@@ graphiql.html
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>GraphiQL</title>
    <style>
      body {
        height: 100%;
        margin: 0;
        width: 100%;
        overflow: hidden;
      }

      #graphiql {
        height: 100vh;
      }
    </style>

    <!--
      This GraphiQL example depends on Promise and fetch, which are available in
      modern browsers, but can be "polyfilled" for older browsers.
      GraphiQL itself depends on React DOM.
      If you do not want to rely on a CDN, you can host these files locally or
      include them directly in your favored resource bundler.
    -->
    <script
      src="https://unpkg.com/react@17/umd/react.development.js"
      integrity="sha512-Vf2xGDzpqUOEIKO+X2rgTLWPY+65++WPwCHkX2nFMu9IcstumPsf/uKKRd5prX3wOu8Q0GBylRpsDB26R6ExOg=="
      crossorigin="anonymous"
    ></script>
    <script
      src="https://unpkg.com/react-dom@17/umd/react-dom.development.js"
      integrity="sha512-Wr9OKCTtq1anK0hq5bY3X/AvDI5EflDSAh0mE9gma+4hl+kXdTJPKZ3TwLMBcrgUeoY0s3dq9JjhCQc7vddtFg=="
      crossorigin="anonymous"
    ></script>

    <!--
      These two files can be found in the npm module, however you may wish to
      copy them directly into your environment, or perhaps include them in your
      favored resource bundler.
     -->
    <link rel="stylesheet" href="https://unpkg.com/graphiql/graphiql.min.css" />
  </head>

  <body>
    <div id="graphiql">Loading...</div>
    <script
      src="https://unpkg.com/graphiql/graphiql.min.js"
      type="application/javascript"
    ></script>
    <script>
      ReactDOM.render(
        React.createElement(GraphiQL, {
          fetcher: GraphiQL.createFetcher({
            url: '/graphql'
          }),
          defaultEditorToolsVisibility: true,
        }),
        document.getElementById('graphiql'),
      );
    </script>
  </body>
</html>
