/*
	This extends the /oomponents/singleton.cf object.
	This is instantiated automatically and stored in the appliation scope as application.s3
*/

component output="false" displayname="s3" extends="singleton" {
	variables.bucketBase = 'JDP-office-';
	variables.bucket = '';
	variables.directory = 'files/';

	// Conditionally set variables based on environment
	if(application.environment == 'local'){
		//S3 Dev Credentials and settings
		variables.envSettings = structNew();
		variables.envSettings.accessKey = '[key]';
		variables.envSettings.secretKey = '[secret]';
		variables.envSettings.bucketSuffix = '-dev';
	} else if(application.environment == 'qa'){
		//S3 QA Credentials and settings
		variables.envSettings = structNew();
		variables.envSettings.accessKey = '[key]';
		variables.envSettings.secretKey = '[secret]';
		variables.envSettings.bucketSuffix = '-qa';
	} else if(application.environment == 'staging'){
		//S3 QA/Staging Credentials and settings
		variables.envSettings = structNew();
		variables.envSettings.accessKey = '[key]';
		variables.envSettings.secretKey = '[secret]';
		variables.envSettings.bucketSuffix = '-qa';
	} else if(application.environment == 'uat'){
		//S3 UAT Credentials and settings
		variables.envSettings = structNew();
		variables.envSettings.accessKey = '[key]';
		variables.envSettings.secretKey = '[secret]';
		variables.envSettings.bucketSuffix = '-uat';
	} else if(application.environment == 'prod'){
		//S3 Dev Credentials and settings
		variables.envSettings = structNew();
		variables.envSettings.accessKey = '[key]';
		variables.envSettings.secretKey = '[secret]';
		variables.envSettings.bucketSuffix = '';
	} 

	public function init(officeId = 1){
		variables.officeId = officeId;

		variables.bucket = variables.bucketBase & variables.officeId & variables.envSettings.bucketSuffix;
		variables.path =  's3://' & variables.envSettings.accessKey & ':' & variables.envSettings.secretKey & '@' & variables.bucket & '/' & variables.directory;
	}

	public function changeOffice(officeId){
		variables.officeId = officeId;

		// reset officeId.  To facilitate global functionality that spans offices.
		variables.bucket = variables.bucketBase & variables.officeId & variables.envSettings.bucketSuffix;
		variables.path = 's3://' & variables.envSettings.accessKey & ':' & variables.envSettings.secretKey & '@' & variables.bucket & '/' & variables.directory;
	}

	public binary function read(file) {
		var _file = '';
		try {
			_file = fileReadBinary(variables.path & lcase(file));			
		} catch (any e) {
			try {
				_file = fileReadBinary(variables.path & ucase(file));
			} catch (any e2) {
				writeOutput('Cannot find file: s3://' & variables.bucket & file & '<br />');
				emailReadError(e2, file);
				abort;
			}
		}
		return _file;
	}

	public function displayFile(file) {
		var content = '';
		try {
			content = fileReadBinary("#variables.path#\#lcase(file)#");
			cfcontent( type="application/pdf", reset="true", variable=content);
		} catch (any e) {
			try {
				content = fileReadBinary("#variables.path#\#ucase(file)#");
				cfcontent( type="application/pdf", reset="true", variable=content);
			} catch (any e2) {
				writeOutput('Cannot find file: s3://' & variables.bucket & file & '<br />');
				emailReadError(e2, document);
				abort;
			}		
		}
	}
	public function writePDF(file, content){
		try {
			cfpdf( 	action="write",
					destination=variables.path & lcase(file),
					overwrite="yes",
					source="content");	
		} catch (any e) {
			writeOutput('Cannot write file: s3://' & variables.bucket & file & '<br />');
			emailWriteError(e, file);
		}
	}

	public function write(file, content){
		try {
			fileWrite(variables.path & lower(file), toBinary(content));	
		} catch (any e) {
			writeOutput('Cannot write file: s3://' & variables.bucket & file & '<br />');
			emailWriteError(e, file);
		}
	}

	public function setDirectory(remoteDirectory){
		variables.directory = remoteDirectory;
		variables.path = 's3://' & variables.envSettings.accessKey & ':' & variables.envSettings.secretKey & '@' & variables.bucket & '/' & variables.directory;
	}

	public function getDirectory(){
		return variables.directory;
	}

	public function createDirectory(directoryName){
		// Creates a sub-directory under the default directory in variables.directory
		directoryCreate(variables.bucket & directoryName);
	}

	public function getPath(){
		return this.path;
	}

	private function emailWriteError(error, file){
		body = '<h2>An error occured trying to write the file ' & file & ' to the S3 bucket: ' & variables.bucket & '</h2><br />';
		body &= error;

		mailObject = new mail();
		mailObject.setServer([server]);
		mailObject.setTo('jeff@jones-us.com');
		mailObject.setFrom('jeff@jones-us.com');
		mailObject.setSubject('An error occured writing to S3');
		mailObject.setType('html');
		mailObject.send(body = body);
	}

	private function emailReadError(error, file){
		body = '<h2>An error occured trying to read the file ' & file & ' from the S3 bucket: ' & variables.bucket & '</h2><br />';
		body &= error;

		mailObject = new mail();
		mailObject.setServer([server]);
		mailObject.setTo('jeff@jones-us.com');
		mailObject.setFrom('jeff@jones-us.com');
		mailObject.setSubject('An error occured reading from S3');
		mailObject.setType('html');
		mailObject.send(body = body);
	}
}