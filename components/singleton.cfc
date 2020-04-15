 component displayname="singleton" output="false" {
	public function getInstance(){
		var displayname = getMetadata(this).displayname;

		if(!structKeyExists(application, displayname)){
			application[displayname] = this;
		}

		init();
		return application[displayname];
	}
}