require 'sinatra'
require 'haml'
require 'thin'
require './secure'
require 'data_mapper'
require 'dm-postgres-adapter'
require 'pg'
require './blog'

enable :sessions

DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/password.db')

class Password
  include DataMapper::Resource

  property :id, Serial
  property :username, String
  property :password, Text
end

DataMapper.finalize
Password.auto_upgrade!

response = Rack::Response.new

def validate_username(username)
  username =~ /^[a-zA-Z0-9_-]{3,20}$/
end

def validate_password(password)
  password =~ /^.{3,20}$/
end

def validate_email(email)
  email =~ /^[\S]+@[\S]+\.[\S]+$/
end

def write_form(username_error='', password_error='', verify_error='', email_error='')
  @invalid_username = username_error
  @invalid_password = password_error
  @invalid_verify = verify_error
  @invalid_email = email_error

  haml :signup, :locals =>
    {	:username => params[:username],
     	:password => params[:password],
    	:verify => params[:verify],
    	:email => params[:email]
    }
end

def name_in_database?(name)
  entries = Password.all
  entries.each do |e|
    return true if e.username == make_secure_value(name)
  end
  return nil
end

def name_and_password_in_database?(name, password)
  secure_name = make_secure_value(name)
  pw = Password.all(:username => secure_name)
  if pw[0]
    pw[0].password =~ /^([^,]*),(.*)/
    if (get_value_from_hash(pw[0].username) == name) && check_for_validity(name, password, pw[0].password)
      return true
    end
  else
    return nil
  end
end

get '/signup' do
  haml :signup
end

post '/signup' do
  @valid_input = true

  if validate_username(params[:username]) == nil
    @invalid_username = %Q{This is not a valid username.}
    @valid_input = false
  elsif name_in_database?(params[:username])
    @invalid_username = %Q{This user already exists.}
    @valid_input = false
  else
    @invalid_username = ''
  end

  if validate_password(params[:password]) == nil
    @invalid_password = %Q{This is not a valid password.}
    @valid_input = false
  else
    @invalid_password = ''
  end

  if params[:password] != params[:verify]
    @invalid_verify = %Q{The passwords do not match.}
    @valid_input = false
  else
    @invalid_verify = ''
  end

  if (params[:email] != '') && (validate_email(params[:email]) == nil)
    @invalid_email = %Q{This is not a valid email address.}
    @valid_input = false
  else
    @invalid_email = ''
  end

  if @valid_input == true
    password_hash = make_password_hash(params[:username], params[:password], make_salt)
    session[:username] = make_secure_value params[:username]
    entry = Password.create(:username => session[:username], :password => password_hash)
    redirect '/welcome'
  else
    write_form(@invalid_username, @invalid_password, @invalid_verify, @invalid_email)
  end
end

get '/login' do
  haml :login
end

post '/login' do
  @username = params[:username]
  @password = params[:password]
  if name_and_password_in_database?(@username, @password)
    session[:username] = make_secure_value @username
    @invalid_login = ''
    redirect '/welcome'
  else
    @invalid_login = 'Invalid login'
  end

  haml :login
end

get '/welcome' do
  if session[:username]
    @username = get_value_from_hash session[:username]
    session[:username] = nil
    session.clear
    haml :welcome
  else
    redirect '/'
  end
end

get '/logout' do
  redirect '/signup'
end
