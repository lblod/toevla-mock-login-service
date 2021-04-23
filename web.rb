require_relative 'mock_login_service/sparql_queries.rb'

## Monkeypatch sparql-client with mu-auth-sudo header
require_relative 'auth_extensions/sudo'
include AuthExtensions::Sudo

###
# POST /sessions
#
# Body
# data: {
#   relationships: {
#     account:{
#       data: {
#         id: "account_id",
#         type: "accounts"
#       }
#     }
#   },
#   type: "sessions"
# }
#
# OR
#
# data: {
#   relationships: {
#     point-of-interest:{
#       data: {
#         id: "point_of_interest_id",
#         type: "points-of-interest"
#       }
#     }
#   },
#   type: "sessions"
# }
#
#
# Returns 201 on successful login
#         400 if session header is missing
#         400 on login failure (incorrect user/password or inactive account)
###

post '/sessions' do
  content_type 'application/vnd.api+json'

  ###
  # Validate headers
  ###
  validate_json_api_content_type(request)

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?

  rewrite_url = rewrite_url_header(request)
  error('X-Rewrite-URL header is missing') if rewrite_url.nil?


  ###
  # Validate request
  ###

  data = @json_body['data']

  validate_resource_type('sessions', data)
  error('Id paramater is not allowed', 400) if not data['id'].nil?

  account_id = data.dig("relationships","account","data","id")
  poi_id = data.dig("relationships","point-of-interest","data","id")

  has_account_id_supplied = account_id && true || false
  has_poi_id_supplied = poi_id && true || false

  error('an account or a point of interest should be linked') unless has_account_id_supplied or has_poi_id_supplied
  error('either account or point of interest should be linked, not both') if has_account_id_supplied and has_poi_id_supplied

  ###
  # Validate login
  ###
  if has_account_id_supplied
    accounts = select_account( account_id )
    error('account not found.', 400) if accounts.empty?
    account_info = accounts.first
  else # must have poi supplied
    poi = select_poi( poi_id )
    error('PointOfInterest not found.', 400) unless poi
    account_info = ensure_account_for_poi( poi_id )
  end

  ###
  # Remove old sessions
  ###
  remove_session(session_uri)

  ###
  # Insert new session
  ###
  session_id = generate_uuid()
  insert_new_session_for_account(account_info[:uri].to_s, session_uri, session_id)

  status 201
  headers['mu-auth-allowed-groups'] = 'CLEAR'
  {
    links: {
      self: rewrite_url.chomp('/') + '/current'
    },
    data: {
      type: 'sessions',
      id: session_id
    },
    relationships: {
      account: {
        links: {
          related: "/accounts/#{session_id}"
        },
        data: {
          type: "accounts",
          id: account_info[:id]
        }
      }
    }
  }.to_json
end


###
# DELETE /sessions/current
#
# Returns 204 on successful logout
#         400 if session header is missing or session header is invalid
###
delete '/sessions/current/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?


  ###
  # Get account
  ###

  result = select_account_by_session(session_uri)
  error('Invalid session') if result.empty?

  ###
  # Remove session
  ###

  remove_session( session_uri )

  status 204
  headers['mu-auth-allowed-groups'] = 'CLEAR'
end


###
# GET /sessions/current
#
# Returns 200 if current session exists
#         400 if session header is missing or session header is invalid
###
get '/sessions/current/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?


  ###
  # Get account
  ###

  result = select_account_by_session(session_uri)
  error('Invalid session') if result.empty?
  session = result.first

  rewrite_url = rewrite_url_header(request)

  status 200
  {
    links: {
      self: rewrite_url.chomp('/') + '/current'
    },
    data: {
      type: 'sessions',
      id: session[:session_uuid]
    },
    relationships: {
      account: {
        links: {
          related: "/accounts/#{session[:account_uuid]}"
        },
        data: {
          type: "accounts",
          id: session[:account_uuid]
        }
      }
    }
  }.to_json
end

###
# GET /pois
#
# Returns 200 with available poinst-of-interest in body
###
get '/pois/?' do
  # TODO: Add param filter
  # TODO: Add param page[size] and page[number]
  content_type 'application/vnd.api+json'

  pois = list_pois()

  status 200
  {
    data: pois.map do |poi|
      {
        type: "points-of-interest",
        id: poi.id,
        attributes: {
          label: poi.label
        }
      }
    end,
    meta: {
      count: amount_of_pois
    }
  }.to_json
end

###
# Helpers
###

helpers MockLoginService::SparqlQueries
