require_relative '/usr/src/app/sinatra_template/utils.rb'

module MockLoginService
  module SparqlQueries
    include SinatraTemplate::Utils

    ACCOUNTS_GRAPH_BASE = "http://data.toevla.org/graphs/accounts/"

    PREFIXES = """
      PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
      PREFIX musession: <http://mu.semte.ch/vocabularies/session/>
      PREFIX muaccount: <http://mu.semte.ch/vocabularies/account/>
      PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
      PREFIX dc: <http://purl.org/dc/elements/1.1/>
      PREFIX adres: <https://data.vlaanderen.be/ns/adres#>
      PREFIX foaf: <http://xmlns.com/foaf/0.1/>
      """
    def remove_session(session)
      # Removes current login info of the current session.
      update """
        #{PREFIXES}
        DELETE {
          GRAPH ?a {
            <#{session}> ?p ?o.
          }
        } WHERE {
          GRAPH ?a {
            <#{session}> ?p ?o.
          }
        }
      """
    end

    def insert_new_session_for_account(account, session_uri, session_id)
      # PRE account exists and has a UUID
      now = DateTime.now

      account_info = query """
        #{PREFIXES}
        SELECT ?account_id
        WHERE {
           GRAPH ?a {
             #{sparql_escape_uri account} a foaf:OnlineAccount;
                                          mu:uuid ?account_id
           }
        }
      """

      if account_info && account_info.first
        account_id = account_info.first[:account_id]
      else
        raise "No account info found"
      end

      graph = "#{ACCOUNTS_GRAPH_BASE}#{account_id}"

      update """
        #{PREFIXES}
        PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
        INSERT DATA {
          GRAPH #{sparql_escape_uri graph} {
            #{sparql_escape_uri session_uri} a musession:Session;
                                             mu:uuid #{sparql_escape_string session_id};
                                             musession:account #{sparql_escape_uri account};
                                             dc:modified #{sparql_escape_datetime now.to_s} .
          }
        }
      """
    end

    def select_account_by_session(session)
      query """
        #{PREFIXES}
        SELECT ?account ?session_uuid ?account_uuid WHERE {
          GRAPH ?a {
            #{sparql_escape_uri session} musession:account ?account;
                                         mu:uuid ?session_uuid.
            ?account mu:uuid ?account_uuid.
          }
        }
      """
    end

    def select_account(id)
      query """
        #{PREFIXES}
        SELECT ?uri ?id WHERE {
          GRAPH <#{ACCOUNTS_GRAPH_BASE}#{id}> {
            BIND( #{sparql_escape_string id} AS ?id )
            ?uri a foaf:OnlineAccount;
                 mu:uuid ?id.
          }
        }
      """
    end

    def ensure_account_for_poi( id )
      # NOTE: Assumes poi for id exists

      # 1. Query to find an account for this PointOfInterest
      find_account_query = """
        #{PREFIXES}
        SELECT ?uri ?id WHERE {
          GRAPH ?g {
            ?poi a adres:AdresseerbaarObject;
                 mu:uuid #{sparql_escape_string id}.
          }
          GRAPH ?a {
            ?uri ext:hasRole/ext:actsOn ?poi;
                 mu:uuid ?id.
          }
        }
        LIMIT 1
      """

      account = query(find_account_query).first

      if !account
        # 2. Create an account, with a DataEntryRole for the given PointOfInterest"
        account_uuid = generate_uuid
        account_uri = "http://data.toevla.org/accounts/#{account_uuid}"
        role_uuid = generate_uuid
        role_uri = "http://data.toevla.org/roles/#{role_uuid}"

        account_graph = "#{ACCOUNTS_GRAPH_BASE}#{account_uuid}"

        insert_account_query = """
          #{PREFIXES}
          INSERT {
            GRAPH #{sparql_escape_uri account_graph} {
              #{sparql_escape_uri account_uri} a foaf:OnlineAccount;
                                               mu:uuid #{sparql_escape_string account_uuid};
                                               ext:hasRole #{sparql_escape_uri role_uri}.
              #{sparql_escape_uri role_uri} a ext:Role, ext:DataEntryRole;
                                            mu:uuid #{sparql_escape_string role_uuid};
                                            ext:actsOn ?poi.
            }
          } WHERE {
            GRAPH ?m {
              ?poi a adres:AdresseerbaarObject;
                   mu:uuid #{sparql_escape_string id}.
            }
          }
        """

        update( insert_account_query )

        { uri: account_uri, id: account_uuid }
      else
        account
      end
    end

    def select_poi(id)
      query = """
        #{PREFIXES}

        SELECT ?uri WHERE {
          GRAPH ?graph {
            ?uri a adres:AdresseerbaarObject;
                 mu:uuid #{sparql_escape_string id}.
          }
        }
      """

      query( query ).first
    end
  end
end
