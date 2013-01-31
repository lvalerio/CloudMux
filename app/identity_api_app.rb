require 'sinatra'

class IdentityApiApp < ApiBase
  get '/countries.json' do
    countries = Country.all
    query = Query.new(Country.count, 1, 0, 500)
    country_query = CountryQuery.new(query, countries).extend(CountryQueryRepresenter)
    [OK, country_query.to_json]
  end

  get '/:id.json' do
    account = Account.find(params[:id])
    account.extend(AccountRepresenter)
    account.to_json
  end

  post '/' do
    new_account = Account.new.extend(UpdateAccountRepresenter)
    new_account.from_json(request.body.read)
    if new_account.valid?
	  # Create organization if account does not belong to one
	  if new_account.org_id.nil?
		if new_account.company.nil?
			new_account.company = "MyOrganization"
		end
		org = Org.new.extend(UpdateOrgRepresenter)
		org.name = new_account.company
		org.save!
		Group.create!(:name => "Development", :description => "default development group", :org => org)
		Group.create!(:name => "Test", :description => "default test group", :org => org)
		Group.create!(:name => "Stage", :description => "default stage group", :org => org)
		Group.create!(:name => "Production", :description => "default production group", :org => org)
	  else
		org_id = new_account.org_id
		new_account.org_id = nil
		org = Org.find(org_id)
		if new_account.company.nil?
			new_account.company = org.name
		end
	  end
	  new_account.save!
	  org.accounts << new_account
      # refresh without the Update representer, so that we don't serialize private data back
      account = Account.find(new_account.id).extend(AccountRepresenter)
      [CREATED, account.to_json]
    else
      message = Error.new.extend(ErrorRepresenter)
      message.message = "#{new_account.errors.full_messages.join(";")}"
      message.validation_errors = new_account.errors.to_hash
      [BAD_REQUEST, message.to_json]
    end
  end

  post '/auth' do
    if params[:login].blank? or params[:password].blank?
      message = Error.new.extend(ErrorRepresenter)
      message.message = "Login and password are required"
      return [BAD_REQUEST, message.to_json]
    end

    account = Account.find_by_login(params[:login])
    if !account.nil? and account.auth(params[:password])
      account.extend(AccountRepresenter)
      return [OK, account.to_json]
    end

    message = Error.new.extend(ErrorRepresenter)
    message.message = "Invalid login or password"
    return [NOT_AUTHORIZED, message.to_json]
  end

  put '/:id' do
    update_account = Account.find(params[:id])
    update_account.extend(UpdateAccountRepresenter)
    update_account.from_json(request.body.read)
    if update_account.valid?
      update_account.save!
      # refresh without the Update representer, so that we don't serialize the password data back across
      account = Account.find(update_account.id).extend(AccountRepresenter)
      [OK, account.to_json]
    else
      message = Error.new.extend(ErrorRepresenter)
      message.message = "#{update_account.errors.full_messages.join(";")}"
      message.validation_errors = update_account.errors.to_hash
      [BAD_REQUEST, message.to_json]
    end
  end

  # Delete a user
  delete '/:id' do
	  account = Account.find(params[:id])
	  account.delete
	  [OK]
  end

  # Register a new cloud account to an existing user account
  post '/:id/:cloud_id/cloud_accounts' do
    update_account = Account.find(params[:id])
    cloud_account = CloudAccount.new.extend(UpdateCloudAccountRepresenter)
    cloud_account.from_json(request.body.read)
    update_account.add_cloud_account!(params[:cloud_id], cloud_account)
    update_account.extend(AccountRepresenter)
    [CREATED, update_account.to_json]
  end

  # Update an existing cloud account
  put '/:id/cloud_accounts/:cloud_account_id' do
	  account = Account.find(params[:id])
	  update_cloud_account = account.cloud_account(params[:cloud_account_id])
	  if update_cloud_account.nil?
		  return [NOT_FOUND]
	  end
	  update_cloud_account.extend(UpdateCloudAccountRepresenter)
	  update_cloud_account.from_json(request.body.read)
	  if update_cloud_account.valid?
		  update_cloud_account.save!
		  updated_cloud_account = account.cloud_account(update_cloud_account.id)
		  updated_cloud_account.extend(CloudAccountRepresenter)
		  [OK, updated_cloud_account.to_json]
	  else
		  message = Error.new.extend(ErrorRepresenter)
		  message.message = "#{update_cloud_account.errors.full_messages.join(";")}"
		  message.validation_errors = update_cloud_account.errors.to_hash
		  [BAD_REQUEST, message.to_json]
	  end
  end

  # Remove an existing cloud account from an existing user account
  delete '/:id/cloud_accounts/:cloud_account_id' do
    update_account = Account.find(params[:id])
    update_account.remove_cloud_account!(params[:cloud_account_id])
    update_account.extend(AccountRepresenter)
    [OK, update_account.to_json]
  end

  # Register a new key pair for a cloud account
  # Note: no longer needed, as they query AWS for key pairs. Not sure how other cloud providers will need this handled, so will leave for now
  post '/:id/:cloud_account_id/key_pairs' do
    update_account = Account.find(params[:id])
    key_pair = KeyPair.new.extend(UpdateKeyPairRepresenter)
    key_pair.from_json(request.body.read)
    update_account.add_key_pair!(params[:cloud_account_id], key_pair)
    update_account.extend(AccountRepresenter)
    [CREATED, update_account.to_json]
  end

  # Register a new key pair for a cloud account
  # Note: no longer needed, as they query AWS for key pairs. Not sure how other cloud providers will need this handled, so will leave for now
  delete '/:id/:cloud_account_id/key_pairs/:key_pair_id' do
    update_account = Account.find(params[:id])
    update_account.remove_key_pair!(params[:cloud_account_id], params[:key_pair_id])
    update_account.extend(AccountRepresenter)
    [OK, update_account.to_json]
  end

  # returns a cloud account that exists within a user's account. This is strictly for provisioning purposes, as cloud accounts do not exist outside of an account
  get '/cloud_accounts/:id.json' do
    cloud_account = Account.find_cloud_account(params[:id])
    if cloud_account.nil?
      [NOT_FOUND]
    else
      cloud_account.extend(CloudAccountRepresenter)
      [OK, cloud_account.to_json]
    end
  end

  # Log a cloud action made by user with cloud account
  post '/:id/:cloud_account_id/audit_logs' do
	  update_account = Account.find(params[:id])
	  audit_log = AuditLog.new.extend(AuditLogRepresenter)
	  audit_log.from_json(request.body.read)
	  update_account.add_audit_log!(params[:cloud_account_id], audit_log)
	  update_account.extend(AccountRepresenter)
	  [CREATED, update_account.to_json]
  end
  
  # Capture cloud resource properties
  post '/:id/:cloud_account_id/cloud_resources' do
	  update_account = Account.find(params[:id])
	  cloud_resource = CloudResource.new.extend(CloudResourceRepresenter)
	  cloud_resource.from_json(request.body.read)
	  update_account.add_cloud_resource!(params[:cloud_account_id], cloud_resource)
	  update_account.extend(AccountRepresenter)
	  [CREATED, update_account.to_json]
  end  
  
  # Add a permission to the user account
  post '/:id/permissions' do
	update_account = Account.find(params[:id])
	permission = Permission.new.extend(UpdatePermissionRepresenter)
    permission.from_json(request.body.read)
    update_account.add_permission!(permission)
    update_account.extend(AccountRepresenter)
    [CREATED, update_account.to_json]
  end
  
  # Remove a permission to the user account
  delete '/:id/permissions/:permission_id' do
	update_account = Account.find(params[:id])
    update_account.remove_permission!(params[:permission_id])
    update_account.extend(AccountRepresenter)
    [OK, update_account.to_json]
  end
end
