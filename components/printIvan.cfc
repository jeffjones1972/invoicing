component output="true" {
	this.version = '2.00';
	this.datasource = application.dsrc1;
	this.invoices = structNew();
	this.userId = 0;

	variables.tempPath = '';

	// Static variables
	variables.FROMADDRESS = 'invoicing@jones-us.com';

	//variables.NL = CreateObject("java", "java.lang.System").getProperty("line.separator"); // Get system specific newline character
	variables.NL = '<br />'; // HTML br as we are using cfhtmltopdf
	variables.DBRPTLIST = 'eMail Invoice'; // Static for DbRepList in DocumentBatches
	this.EMAILSERVER = '';
	// Statuses
	variables.PRINTED = 100;
	variables.MAILROOM = 50;

	public function init(userId, officeId, scheduled = false){
		if (scheduled == true){
			this.S3 = server.S3;
			changeOffice(officeId);
			getInvoiceMetaData(officeId);
		} else {
			this.S3 = application.S3;
			changeOffice(officeId);
			getInvoiceMetaData(officeId);
		}
		this.userId = userId;
		setEmailServer();

		//writeDump(var = this, abort = true);
	}

	public function changeOffice(officeId){
		server.S3.changeOffice(officeId);
		variables.tempPath = '/tmp/invoicing/' & officeId & '/'; // Path to generate the temp PDFs for processing.
	}

	private function setEmailServer(officeId) {
		var emailServer = queryExecute("select settingValue from Environment where settingName = 'EmailServer' and officeId = officeId", officeId: officeId,{datasource: this.datasource});
		this.EMAILSERVER = emailServer.settingValue;

		return;
	}

	private function formatPhoneNumber(phone){
		//Clean Phone
		phone = reReplace(phone, "[^0-9]", "", "ALL");

		// If phone is not 10 characters, exit
		if(len(phone) != 10){
			return 0;
		}
		
		// Create formated phone
		areaCode =left(phone,3);
		prefix = mid(phone,4,3);
		number = right(phone,4);

		phone = areaCode & '.' & prefix & '.' & number;

		return phone;
	}

	private function copyInvoicesToTemp(){
		var emailInvoice = '';
		variables.threadMessg = ""; //for troubleshooting
		variables.s3Invoices = StructCount(this.invoices);
		variables.s3InvoicesWritten = 0;
		for(invoice in this.invoices){
		 	changeOffice(this.invoices[invoice].officeId);
			variables.clientsCnt = StructCount(this.invoices[invoice].clients);
			variables.clientsProc = 0;
			for(clientId in this.invoices[invoice].clients){		 		
		 		
				thread	name="#invoice#_#clientid#_#DateTimeFormat(Now(),'hhnnssl')##randRange(1,100)#"
						action="run"
						trdinvoice = invoice
						trdclientid = clientid
						tempEmailPath = variables.tempPath & 'email/'
						tempMailPath = variables.tempPath & 'mail/'
						tempPnHPath = variables.tempPath & 'printAndHold/'
						printAndHold = this.invoices[invoice].data.printAndHold 
						method = this.invoices[invoice].clients[clientId].clientDeliveryMethod
		 				role = this.invoices[invoice].clients[clientId].role

						{
					
					//variables.threadMessg = variables.threadMessg & "<br>" & thread.name & " "; //for troubleshooting

					try{
						if(printAndHold == 1){
							//variables.threadMessg = variables.threadMessg & " Printhold "; //uncomment for troubleshooting
							
							generatePrintAndHoldCover(trdinvoice,trdclientid);
							if(role == 11){
								generateMailCCCover(trdinvoice,trdclientid);
								fileWrite(tempPnHPath & this.invoices[trdinvoice].clients[trdclientid].processingDocumentName, this.invoices[trdinvoice].data.invoicePDF);
							}
							fileWrite(tempPnHPath & this.invoices[trdinvoice].clients[trdclientid].processingDocumentName, this.invoices[trdinvoice].data.invoicePDF);
							
						} else if (method == 'E'){
							//variables.threadMessg = variables.threadMessg & " Email "; //uncomment for troubleshooting
							
							thread.emailInvoice = this.invoices[trdinvoice].data.invoicePDF;

							// Protect PDFs to be electronically distributed.
							cfpdf(  action="protect", 
									source="thread.emailInvoice", 
									newOwnerPassword="MyP@ssw0rd", 
									overwrite="true", 
									encrypt="AES_128", 
									permissions="allowassembly,
												AllowDegradedPrinting,
												AllowPrinting,
												AllowScreenReaders,
												AllowSecure,
												AllowScreenReaders", 
									destination=tempEmailPath & this.invoices[trdinvoice].data.emailDocumentName);
							
						} else {
							//variables.threadMessg = variables.threadMessg & " Mail "; //uncomment for troubleshooting
							
							if (role == 11){
								generateMailCCCover(invoice,trdclientid);
							}
							fileWrite(tempMailPath & this.invoices[invoice].clients[trdclientid].processingDocumentName, this.invoices[invoice].data.invoicePDF);
										
						}
					}catch (any e){
						WriteLog( type="#e.type#" ,text="copyInvoicesToTemp Invoice: #trdinvoice# Messg:#e.message#" );		
					}
					
					variables.clientsProc = variables.clientsProc + 1;
				}
				
			}
			while(variables.clientsProc LT variables.clientsCnt){
				sleep(10);
			}
			thread	name="s3#invoice#"
					action="run" 
					trdinvoice=invoice {
				try{
					this.S3.writePDF(this.invoices[trdinvoice].data.documentName, this.invoices[trdinvoice].data.invoicePDF); 
				}catch(any e){
					WriteLog( type="#e.type#" ,text="S3WritePDF Invoice: #trdinvoice# Messg:#e.message#");			
				}
				variables.s3InvoicesWritten = variables.s3InvoicesWritten + 1;
			}	
		}
		while(variables.s3InvoicesWritten LT variables.s3Invoices){
				sleep(10);
		}
		//Writeoutput("<br> Done with loop"); //for troubleshooting
		//writeoutput(variables.threadMessg); //for troubleshooting
		// Create the merged PDFs for printing
				
		thread	name="mergeMail"
				action="run" {
			try{ 
				mergePDFs('mail'); 
			}catch(any e){
				WriteLog( type="#e.type#" ,text="Merge mail: Messg:#e.message#" );
			}
		}		
		thread	name="mergePNH"
				action="run" {
			try{ 
				mergePDFs('printAndHold'); 
			}catch(any e){
				WriteLog( type="#e.type#" ,text="Merge printAndHold: Messg:#e.message#" );
			}
		}
		thread action="join" name="mergeMail,mergePNH" timeout="10000" {}
		
		//Writeoutput("<br> Done with merges");	//for troubleshooting			
	}

	public function emailInvoices(officeId, status) {
		getInvoiceMetaData(officeId,'','',status);
		changeOffice(officeId);
		for(invoice in this.invoices){
			for (record in this.invoices[invoice].clients){
				if(this.invoices[invoice].clients[record].clientDeliveryMethod == 'E' and this.invoices[invoice].data.printAndHold == 0){
					var documentId = this.invoices[invoice].data.documentId;
					var documentName = this.invoices[invoice].data.documentName;
					var emailDocumentName = this.invoices[invoice].data.emailDocumentName;
					var emailAddresses = listRemoveDuplicates(this.invoices[invoice].emailAddresses, ",", true);
					var bccAddress = this.invoices[invoice].data.bccEmailAddress;
					var projectName = this.invoices[invoice].data.projectName;
					var clientGUID = this.invoices[invoice].data.clientGUID;
					var deliveryMethod = 2; //Email
					var filePath = variables.tempPath & '\email\';
					this.invoices[invoice].data.emailBody = generateEmail(invoice);
					this.invoices[invoice].data.emailSubject = 'Invoice for Project ' & projectName;

					mailObject = new mail();
					mailObject.setServer(this.EMAILSERVER);
					mailObject.setTo(emailAddresses);
					mailObject.setBCC(bccAddress);
					mailObject.setFrom(variables.FROMADDRESS);
					mailObject.setSubject(this.invoices[invoice].data.emailSubject);
					mailObject.setType("html");
					mailObject.addParam(file=filePath & emailDocumentName, type="application/pdf");
					mailObject.send(body=this.invoices[invoice].data.emailBody);
					var docBatchResult = newDocumentBatch(1,documentName,variables.DBRPTLIST,this.invoices[invoice].officeId); //DestinationID is irrelavant now that we are using S3.
					var documentBatchId = addDocumentBatch(documentId,docBatchResult,this.invoices[invoice].officeId);
					var documentBatchDistributionResult = newDocumentBatchDistribution(docBatchResult,clientGUID,deliveryMethod,this.invoices[invoice].officeId);
					markDocumentDistributionAsSent(this.invoices[invoice].officeId,documentBatchDistributionResult,this.invoices[invoice].data.emailDocumentName);
				}			
			}			
		}
	}

	public function printInvoices(officeId) {
		var method = 'mail';
		var path = variables.tempPath & method;
		var qryInvoices = directoryList(path, false, "query", "*.pdf", "asc", "file" );
		if(qryInvoices.recordCount > 0){
			moveGenerated(method);
			displayInvoices(method, officeId);			
		} else {

			return;
		}
	}

	public function printAndHoldInvoices(officeId) {
		changeOffice(officeId);
		var method = 'printAndHold';
		var path = variables.tempPath & method;
		var qryInvoices = directoryList(path, false, "query", "*.pdf", "asc", "file" );
		if(qryInvoices.recordCount > 0){
			moveGenerated(method);
			displayInvoices(method, officeId);			
		} else {
			
			return;
		}
	}

	private function displayInvoices(method, officeId){
		changeOffice(officeId);
		var path = variables.tempPath & method & '/';
		var content = fileReadBinary("#path#generated/Invoices.pdf");
		cfcontent( type="application/pdf", reset="true", variable=content);
	}

	public function generatePDFs(){
		cfsetting(requesttimeout="1800" );

		variables.invCount = StructCount(this.invoices);
		variables.invProcessed = 0;
		
		//writeDump(var="invCount: #variables.invCount#");
		
		for(invoice in this.invoices){
			officeId = this.invoices[invoice].officeId;
			changeOffice(officeId);

			var tempEmailPath = variables.tempPath & 'email/';
			var tempMailPath = variables.tempPath & 'mail/';
			var tempPnHPath = variables.tempPath & 'printAndHold/';

		 	if(!directoryExists(tempEmailPath)){
				directoryCreate(tempEmailPath);
			}
		 	if(!directoryExists(tempMailPath)){
				directoryCreate(tempMailPath);
				directoryCreate(tempMailPath & 'generated/');
				directoryCreate(tempMailPath & 'processed/');
			}
		 	if(!directoryExists(tempPnHPath)){
				directoryCreate(tempPnHPath);
				directoryCreate(tempPnHPath & 'generated/');
				directoryCreate(tempPnHPath & 'processed/');
			}
			if(!structKeyExists(this.invoices[invoice].data,'documentName')){
				//Happens if there is no primary invoice recipient, which should not happen.
				this.invoices[invoice].data.documentName = createDocumentName(this.invoices[invoice].data.documentId);
			}			
			thread 	name=this.invoices[invoice].data.invoiceHeaderId 
					action="run" 
					trdinvoice=invoice 
					trddocumentId=this.invoices[invoice].data.documentId
					trddocumentName=this.invoices[invoice].data.documentName 
					trdinvoiceHeaderId=this.invoices[invoice].data.invoiceHeaderId  {
				
				try{
					this.invoices[trdinvoice].data.invoicePDF = generatePDF(trdinvoiceHeaderId);
					this.invoices[trdinvoice].data.invoicePDFProcessed = false;
					addDocumentName(trddocumentId,trddocumentName,this.invoices[trdinvoice].officeId);
					newStatus(trddocumentId,this.invoices[trdinvoice].officeId, variables.PRINTED, this.userId);
				}catch(any e){
					WriteLog( type="#e.type#" ,text="generatePDFs Invoice: #trdinvoice# Message:#e.message#" );	
				}
				variables.invProcessed = variables.invProcessed + 1;	
			}	
			
		}
		while(variables.invProcessed LT variables.invCount){
			sleep(10);
		}
		
		copyInvoicesToTemp();
		return;
	}

	public binary function generatePDF(invoiceHeaderId){
		var content = '';
		var documentName = this.invoices[invoiceHeaderId].data.documentName;
		cfsetting(showdebugoutput="false" ); // Ensure debugging is not generated to the PDF

		try {
			cfhtmltopdf( name="content",
						 overwrite="yes",
						 encryption="none", 
						 marginLeft="0.5",
						 orientation="portrait", 
						 pageType="letter", 
						 unit="in",
						 source='http://invoicing/invoice/#invoiceHeaderId#/preview/yes'){};
		}catch (any e) {
			sendError(e,this.invoices[invoiceHeaderId].officeId, this.invoices[invoiceHeaderId].data.projectNumber);
		}

		return content; 
	}

	private function mergePDFs(method){
		var path = variables.tempPath & method;

		try {
			cfpdf(action="merge", directory="#path#", order="name", ascending="yes",destination="#path#/generated/Invoices.pdf", overwrite="yes", stoponerror="no");
		} catch (any e) {
			// No pdfs for this method.
		}
		return;	
	}

	private function moveGenerated(method) {
		var path = variables.tempPath & '/' & method & '/';
		var fileDestination = path & 'processed/';
		
		var qryInvoices = directoryList(path, false, "query", "*.pdf", "asc", "file" );	
		for (invoice in qryInvoices){
			fileMove(path & invoice.Name, fileDestination & invoice.Name);
			while(!fileExists(fileDestination & invoice.Name)){sleep(10);}
		}	
		return;
	}

	public function getInvoiceMetaData(officeId = '00', invoiceHeaderId = '', method = '', status = variables.MAILROOM){
		var invoiceCount = listLen(invoiceHeaderId,','); // Get how many elements to be processed.
		var datasource = this.datasource;
		var deliveryMethod = '';
		switch(method){
			case "email":
				deliveryMethod = 'E';
				break;
			case "mail":
				deliveryMethod = "M";
				break;
			case "printAndHold":
				deliveryMethod = "M";
				break;
		}

		// Get appropriate invoices
		invoiceSQL = "select top (350)
			p.officeId,
			ih.invoiceHeaderId,
			d.documentId,
			d.documentRejectNote,
			ih.invoiceNumber,
			ih.invoiceDateTime,
			ih.invoiceYear,
			ih.invoiceMonth,
			ih.invoiceClientId,
			ih.invoicePrintAndHold,
			p.projectNumber, 
			p.projectName, 
			p.projectPrintAndHold,
			p.specialInstructions,
			pp.participantType,
			c.clientId,
			c.clientNumber,
			c.invoiceDeliveryMethod,
            c.salutation,
			c.clientFirstName,
            c.clientMiddleName,
            c.clientLastName,	
			c.clientEmail,
			c.address1, 
			c.address2, 
			c.city, 
			c.state, 
			c.zip,
			coalesce(rtrim(eo.directDial),'') directDial,
			p2.settingValue officePhone,
			eo.displayName,
			lower(rtrim(eo.username)) + '@jones-us.com' email,
			eo.signature,
			dbd.batchSent
		from invoiceHdr ih
		    join documents d on ih.headerId = d.documentRowId and d.documentApplicationId = 4
		    join projects p on ih.invoiceProjectId = p.projectId
	    	join employees eo on ih.supervisorId = eo.employeeId
		    join projectParticipants pp on p.projectId = pp.participantProjectId
		    join clients c on pp.participatClientId = c.clientId
	    	join settings s on p.officeId = s.officeId and s.settingName = 'phone'
	    	join settings s2 on p.officeId = s2.PtOfficeId and s2.settingName = 'invoicingVersion'
	    	left outer join documentBatches db on d.documentsDocumentBatchId = db.documentBatchId
	    	left outer join documentBatchDistribution dbd on db.documentBatchId = dbd.distributionDocumentBatchId 
		where (pp.invoice = 1 or pp.participantTypeId = 11) and pp.deleted is null 
		and dbd.batchSent is null and s2.settingValue >= 2.0
		and  documentStatusId = :status ";
		if (officeId == "00"){
			invoiceSQL &= "and officeId = officeId ";
		} else 
			invoiceSQL &= "and officeId = :officeId ";
		}
		if(invoiceCount == 1){
			invoiceSQL &= "and invoiceHeaderId = :invoiceHeaderId ";
		} else if (invoiceCount > 1) {
			invoiceSQL &= "and invoiceHeaderId in (:invoiceHeaderId) ";
		}
		invoiceSQL &= "order by ih.invoiceHeaderId, pp.participantType";

		//writeDump(invoiceSQL);

		// writeDump(var = invoiceSQL, abort = true);
		getInvoiceData = queryExecute(preserveSingleQuotes(invoiceSQL)
									  ,{officeId: officeId,
									  	invoiceHeaderId: invoiceHeaderId, 
									  	deliveryMethod: deliveryMethod, 
									  	status: status}
									  ,{datasource: datasource});
	
		// writeDump(var = getInvoiceData, expand = false);
		//writeDump(var = getInvoiceData, abort = true);
		for (record in getInvoiceData){
			variables.invoiceNumber = record['invoiceNumber'];
			variables.clientEmailList = '';

			//writeDump(record);

			// if(invoiceHeaderId == '')		 {
			// 	var invoiceHeaderId = record['invoiceHeaderId'];
			// }
			// Create structure for variables.
    		primaryClientId = getInvoiceData["invoiceClientId"];
    		clientGUID = getInvoiceData["clientId"];
    		clientID = getInvoiceData["clientNumber"];

    		if(!structKeyExists(this.invoices, record['invoiceHeaderId'])){
    			// Create structure for data storage
	    		this.invoices[record['invoiceHeaderId']]=structNew();
				this.invoices[record['invoiceHeaderId']].data=structNew();
				this.invoices[record['invoiceHeaderId']].clients=structNew();
				this.invoices[record['invoiceHeaderId']].clients[clientID]=structNew();

				//Top level data
    			this.invoices[record['invoiceHeaderId']].emailAddresses = '';
    			this.invoices[record['invoiceHeaderId']].toMail = '';
				this.invoices[record['invoiceHeaderId']].officeId = trim(record['officeId']);

	    		// Invoice data
				this.invoices[record['invoiceHeaderId']].data.projectNumber = trim(record['projectNumber']);
				this.invoices[record['invoiceHeaderId']].data.projectName = trim(record['projectName']);
				this.invoices[record['invoiceHeaderId']].data.invoiceHeaderId = record["invoiceHeaderId"];
				this.invoices[record['invoiceHeaderId']].data.invoiceNumber = record["invoiceNumber"];
				this.invoices[record['invoiceHeaderId']].data.invoiceDate = record["invoiceDateTime"];
				this.invoices[record['invoiceHeaderId']].data.specialInstructions = trim(record['specialInstructions']);
				this.invoices[record['invoiceHeaderId']].data.rejectNote = trim(record['documentRejectNote']);
				this.invoices[record['invoiceHeaderId']].data.documentId = record['documentId'];
				this.invoices[record['invoiceHeaderId']].data.bccEmailAddress = 'ecsmailroom';
				this.invoices[record['invoiceHeaderId']].data.bccEmailAddress &= trim(record['officeId']);
				this.invoices[record['invoiceHeaderId']].data.bccEmailAddress &= '@ecslimited.com';
				this.invoices[record['invoiceHeaderId']].data.projectEngineerDirectDial = trim(record['directDial']);
				this.invoices[record['invoiceHeaderId']].data.projectEngineerOfficePhone = trim(record['officePhone']);
				this.invoices[record['invoiceHeaderId']].data.projectEngineerName = trim(record['displayName']);
				this.invoices[record['invoiceHeaderId']].data.projectEngineerEmail = record['email'];
				this.invoices[record['invoiceHeaderId']].data.projectEngineerSignBlock = trim(record['signature']);

				// Client data
				// Set email and distribution method
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientGUID = trim(clientGUID);
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientID = trim(clientID);
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientEmailAddress = trim(record['clientEmail']);
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientDeliveryMethod = trim(record['invoiceDeliveryMethod']);
				this.invoices[record['invoiceHeaderId']].emailAddresses = listAppend(this.invoices[record['invoiceHeaderId']].emailAddresses, trim(record['clientEmail']));
	    		this.invoices[record['invoiceHeaderId']].clients[clientID].role = trim(record['participantType']);
				this.invoices[record['invoiceHeaderId']].clients[clientID].salutation = record['salutation'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].firstName = record['clientFirstName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].middleName = record['clientMiddleName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].lastName = record['clientLastName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].address1 = record['address1'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].address2 = record['address2'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].city = record['city'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].state = record['state'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].zip = record['zip'];
    		} else {
    			// Add additional client for distribution
				this.invoices[record['invoiceHeaderId']].clients[clientID]=structNew();
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientEmailAddress = trim(record['clientEmail']);
				this.invoices[record['invoiceHeaderId']].clients[clientID].clientDeliveryMethod = trim(record['invoiceDeliveryMethod']);
				//this.invoices[record['invoiceHeaderId']].toEmail = listAppend(this.invoices[record['invoiceHeaderId']].toEmail, trim(record['clientEmail']));
				if(isValid('email',trim(record['clientEmail'])) and trim(record['clientEmail']) != ''){
				this.invoices[record['invoiceHeaderId']].emailAddresses = listAppend(this.invoices[record['invoiceHeaderId']].emailAddresses, trim(record['clientEmail']));
				} else {
					method = 'mail';
					if(trim(record['participantType']) == 11){
					this.invoices[record['invoiceHeaderId']].clients[clientId].seperatorDocumentName = createSeperatorDocumentName(record['invoiceHeaderId'],clientId);
					} else {
						this.invoices[record['invoiceHeaderId']].data.documentName = createDocumentName(record['documentId']);
					}
				}
	    		this.invoices[record['invoiceHeaderId']].clients[clientID].role = trim(record['participantType']);
				this.invoices[record['invoiceHeaderId']].clients[clientID].salutation = record['salutation'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].firstName = record['clientFirstName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].middleName = record['clientMiddleName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].lastName = record['clientLastName'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].address1 = record['address1'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].address2 = record['address2'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].city = record['city'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].state = record['state'];
				this.invoices[record['invoiceHeaderId']].clients[clientID].zip = record['zip'];
    		} 
				if( record['invoicePrintAndHold'] == 'T' or record['projectPrintAndHold'] == 1){
					this.invoices[record['invoiceHeaderId']].data.printAndHold = 1;
					this.invoices[record['invoiceHeaderId']].clients[clientID].printAndHoldDocumentName = createPrintAndHoldDocumentName(record['invoiceHeaderId']);
				} else {
					this.invoices[record['invoiceHeaderId']].data.printAndHold = 0;
				}
				if(trim(record['participantType']) == 11){
					this.invoices[record['invoiceHeaderId']].clients[clientId].seperatorDocumentName = createSeperatorDocumentName(record['invoiceHeaderId'],clientId);
				} else {
					this.invoices[record['invoiceHeaderId']].data.clientGUID = clientGUID;
					this.invoices[record['invoiceHeaderId']].data.documentName = createDocumentName(record['documentId']);
				}
				this.invoices[record['invoiceHeaderId']].clients[clientId].processingDocumentName = createDocumentNameForProcessing(record['invoiceHeaderId'],clientId);
				this.invoices[record['invoiceHeaderId']].data.emailDocumentName = createEmailDocumentName(record['invoiceNumber'], record['invoiceMonth'], record['invoiceYear']);

	    			//Create Questionairre url.
					this.invoices[record['invoiceHeaderId']].data.questionairre = 'href="http://35red.ecslimited.com/survey/script/scwin04.exe';
					this.invoices[record['invoiceHeaderId']].data.questionairre &= '?E_version=4&E_file=';
					this.invoices[record['invoiceHeaderId']].data.questionairre &= 'd:\wwwroot\ecslimited\survey\in01.htm&V_custid=';
					this.invoices[record['invoiceHeaderId']].data.questionairre &= variables.invoiceNumber & '>&V_office=';
					this.invoices[record['invoiceHeaderId']].data.questionairre &= this.invoices[record['invoiceHeaderId']].officeId & '>&V_Inpu"';

					//Create signature block
					this.invoices[record['invoiceHeaderId']].data.signatureBlock = this.invoices[record['invoiceHeaderId']].data.projectEngineerName & '<br />';

					if(trim(this.invoices[record['invoiceHeaderId']].data.projectEngineerSignBlock) != '') {
						this.invoices[record['invoiceHeaderId']].data.signatureBlock 
						&= this.invoices[record['invoiceHeaderId']].data.projectEngineerSignBlock & '<br />';
					}
					if(rtrim(this.invoices[record['invoiceHeaderId']].data.projectEngineerDirectDial) != '') {
						this.invoices[record['invoiceHeaderId']].data.signatureBlock 

						&= formatPhoneNumber(this.invoices[record['invoiceHeaderId']].data.projectEngineerDirectDial) & '<br />';
					}

					if(rtrim(this.invoices[record['invoiceHeaderId']].data.projectEngineerOfficePhone) != '') {
						this.invoices[record['invoiceHeaderId']].data.signatureBlock 
						&= formatPhoneNumber(this.invoices[record['invoiceHeaderId']].data.projectEngineerOfficePhone) & '<br />';
					}

					this.invoices[record['invoiceHeaderId']].data.signatureBlock 
					&= '<a href="mailto:' & this.invoices[record['invoiceHeaderId']].data.projectEngineerEmail & '">';

					this.invoices[record['invoiceHeaderId']].data.signatureBlock 
					&= this.invoices[record['invoiceHeaderId']].data.projectEngineerName & '</a>';
    				var name = '';
					if(trim(this.invoices[record['invoiceHeaderId']].clients[clientID].salutation) != ''){
						name = trim(this.invoices[record['invoiceHeaderId']].clients[clientID].salutation) & ' ';
					}
					if(trim(this.invoices[record['invoiceHeaderId']].clients[clientID].firstName) != ''){
						name &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].firstName) & ' ';
					}
					if(trim(this.invoices[record['invoiceHeaderId']].clients[clientID].middleName) != ''){
						name &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].middleName) & ' ';
					}
					name &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].lastName);

					this.invoices[record['invoiceHeaderId']].clients[clientID].name = name;
					this.invoices[record['invoiceHeaderId']].clients[clientID].address = trim(this.invoices[record['invoiceHeaderId']].clients[clientID].address1) & variables.NL;
					if(trim(this.invoices[record['invoiceHeaderId']].clients[clientID].address2) != ''){
						this.invoices[record['invoiceHeaderId']].clients[clientID].address &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].address2) & variables.NL;
					}
					this.invoices[record['invoiceHeaderId']].clients[clientID].address &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].city) & ', ';
					this.invoices[record['invoiceHeaderId']].clients[clientID].address &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].state) & ' ';
					this.invoices[record['invoiceHeaderId']].clients[clientID].address &= trim(this.invoices[record['invoiceHeaderId']].clients[clientID].zip);
		}
		return;
	}

	private String function createDocumentName(documentId) {
		// Format I & documentId padded with 0 out to 10 places & R.pdf.
		return 'invoice' & numberFormat(documentId,"0000000009") & 'R.pdf';
	}	

	// Create name for processing invoices to sort correctly.
	private String function createDocumentNameForProcessing(invoiceHeaderId, clientId) {
		var role = this.invoices[invoiceHeaderId].clients[clientId].role;
		var documentId = this.invoices[invoiceHeaderId].data.documentId;
		// Format I & documentId padded with 0 out to 10 places & raw_ & clientId & _9.pdf.  Ensures it is last in the sort.
		return 'invoice' & numberFormat(documentId,"0000000009") & 'raw_' & role & '_' & clientId & '_9.pdf';
	}	

	private String function createSeperatorDocumentName(invoiceHeaderId, clientId) {
		var role = this.invoices[invoiceHeaderId].clients[clientId].role;
		var documentId = this.invoices[invoiceHeaderId].data.documentId;
		// Format I & documentId padded with 0 out to 10 places & raw_ & clientId & _0.pdf.  Ensures it is first in the sort.
		return 'invoice' & numberFormat(documentId,"0000000009") & 'raw_' & role & '_' & clientID & '_0.pdf';
	}	

	private String function createPrintAndHoldDocumentName(invoiceHeaderId, clientId) {
		var role = this.invoices[invoiceHeaderId].clients[clientId].role;
		var documentId = this.invoices[invoiceHeaderId].data.documentId;
		// Format I & documentId padded with 0 out to 10 places & raw_ & clientId & _1.pdf.  Ensures it is second in the sort.
		return 'invoice' & numberFormat(documentId,"0000000009") & 'raw_' & role & '_' & clientID & '_1.pdf';
	}	

	private String function createEmailDocumentName(invoiceNumber, invMonth, invYear) {
		// Format I & documentId padded with 0 out to 10 places & R.pdf.
		return 'ECS' & invYear & invMonth & 'invoice' & invoiceNumber & '.pdf';
	}

	private function addDocumentName(documentId, documentName, officeId){
		cfstoredproc( procedure = "AddDocName", datasource=this.datasource){
			cfprocparam( cfsqltype="cf_sql_integer", value=documentId, dbvarname="@documentId" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=documentName, dbvarname="@documentName" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId" );
			cfprocresult( name="result" );
		}

		if(result.documentId <= 0){
			writeOutput("'An error occured adding the documentName to the Documents table.   Error: " & result.documentId);
		}
		return result.documentId;
	}

	//When emailed
	private function newDocumentBatch(destinationId, documentName, reportList, officeId){
		cfstoredproc( procedure = "NewDocBatch", datasource=this.datasource){
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=documentName, dbvarname="@documentBatchName" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=reportList, dbvarname="@DbRptList" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId" );
			cfprocresult( name="result");
		}
		return result.DbId;
	}

	private function addDocumentBatch(documentId, documentBatchId, officeId){
		cfstoredproc( procedure="addDocBatch", datasource=this.datasource ) {
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentId, dbvarname="@documentId" );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentBatchID, dbvarname="@DoDbId");
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId" );
			cfprocresult( name="result" );
		}
		return result.documentId;
	}

	private function newDocumentBatchDistribution(documentBatchId, clientGUID, documentMethod, officeId) {
		cfstoredproc( procedure="NewDocBatchDistribution", datasource=this.datasource ){
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentbatchId, dbvarname="@documentDistributionBatchId" );
			cfprocparam( cfsqltype="CF_SQL_CHAR", value=clientGUID, dbvarname="@documentDistributionClientId" );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentMethod, dbvarname="@methodId" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId" );
			cfprocresult( name="result" );
		}
		return result.DdId;
	}

	private function markDocumentDistributionAsSent(officeId, documentDistributionId, emailFileName){
		cfstoredproc( procedure="vs_MarkDocBatchDistAsSent", datasource=this.datasource ){
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId"  );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentDistributionId, dbvarname="@documentDistributionId" );
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=emailFileName, dbvarname="@filename");
			cfprocresult( name="result" );
		}
	}

	private function newStatus(documentId, officeId, statusId, userId) {
		if(!isNumeric(userId)){userId = 0;} // For scheduled task.
		cfstoredproc( procedure="jc_NewStatusLog", datasource=this.datasource ){
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=documentId, dbvarname="@documentId");
			cfprocparam( cfsqltype="CF_SQL_VARCHAR", value=officeId, dbvarname="@officeId" );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=statusId, dbvarname="@statusId" );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value=userId, dbvarname="@ActedById" );
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value="0", dbvarname="@AssignToId" ); //Assign to nobody
			cfprocparam( cfsqltype="CF_SQL_INTEGER", value="0", dbvarname="@slOverrideId" ); //Override by nobody
			cfprocresult( name="result" );
		}
	}

	//Generate mail print and hold cover
	private function generatePrintAndHoldCover(invoiceHeaderId, clientId){
		cfsetting(showdebugoutput="false" );
		var documentName = this.invoices[invoiceHeaderId].clients[clientId].printAndHoldDocumentName;
		
		var directory = 'printAndHold/';
		changeOffice(this.invoices[invoiceHeaderId].officeId);
		directory = variables.tempPath & '/' & directory;

		var project = this.invoices[invoiceHeaderId].data.projectNumber;
		var specialInstructions='(None)';
		if(len(this.invoices[invoiceHeaderId].data.specialInstructions) > 0){
			specialInstructions = this.invoices[invoiceHeaderId].data.specialInstructions;
		}
		var rejectNote='(None)';
		if(len(this.invoices[invoiceHeaderId].data.rejectNote) > 0){
			rejectNote = this.invoices[invoiceHeaderId].data.rejectNote;
		}

		cfhtmltopdf( destination='#directory##documentName#', 
					 overwrite="yes",
					 encryption="none", 
					 marginLeft="0.5",

					 name='content',
					 orientation="portrait", 
					 pageType="letter", 
					 saveAsName='#documentName#', 
					 unit="in"){
		writeOutput('
		<style>
			##container {border: 0px; position: absolute; width: auto; height: auto; top: 20px; left: 20px; bottom: 20px;right: 20px; clear: both; }
			.block-top {border: 1px solid black; position: absolute; background: lightblue; top: 10px; width: auto; height: 50px; left: 10px; right:10px; }
			##header {border:none; position:absolute; top:68px; width: auto; left: 10px; right: 10px; text-align: center; font-size: 18pt; font-weight: bold; }
			##holdMessage {position:absolute; top: 175px; font-size: 38pt; font-weight: bolder; text-align: center; width: auto; left: 10px; right: 10px; }
			##specialInstructions {position:absolute; top: 235px; font-size: 12pt; font-weight: bold; text-align: center; width: auto; left: 10px; right: 10px; }
			##nonPrintableNotes {position:absolute; top: 695px; font-size: 12pt; font-weight: bold; text-align: center; width: auto; left: 10px; right: 10px; }
			.block-bottom {border: 1px solid black; position: absolute; background: lightblue; bottom: 10px; width: auto; height: 50px; left: 10px; right:10px; }
		</style>

		<cfoutput>
			<div id="container">
				<div class="block-top"></div>
				<div id="header">Invoice for Project: ' & project & '</div>
				<div id="holdMessage">HOLD FOR ATTACHMENTS</div>
				<div id="specialInstructions">Special Instructions: ' & specialInstructions & '</div>
				<div id="nonPrintableNotes">Non Printable Notes: ' & rejectNote & '</div>
				<div class="block-bottom"></div>
			</div>
		</cfoutput>');
		}
	}

	//Generate mail cc cover sheet
	private function generateMailCCCover(invoiceHeaderId, clientId){
		cfsetting(showdebugoutput="false" );
		// writeDump(structKeyExists(this.invoices[invoiceHeaderId].clients[clientId], "sepDocName"));
		// writeDump(var = this.invoices[invoiceHeaderId].clients[clientId], abort = true);
		var documentName = this.invoices[invoiceHeaderId].clients[clientId].seperatorDocumentName;
		
		var directory = '';
		if(this.invoices[invoiceHeaderId].data.printAndHold == 1){
			directory = 'printAndHold/';
		} else {
			directory = 'mail\';
		}
		changeOffice(this.invoices[invoiceHeaderId].officeId);
		directory = variables.tempPath & '/' & directory;
		//writeDump(var = this.invoices[invoiceHeaderId].clients[clientID].name, abort = true);

		cfhtmltopdf( destination='#directory##documentName#', 
					 overwrite="yes",
					 encryption="none", 
					 marginLeft="0.9",
					 marginTop="2.1",
					 name='content',
					 orientation="portrait", 
					 pageType="letter", 
					 saveAsName='#documentName#', 
					 unit="in"){
			writeOutput(this.invoices[invoiceHeaderId].clients[clientID].name & variables.NL);
			writeOutput(this.invoices[invoiceHeaderId].clients[clientID].address);
			writeOutput(variables.NL &variables.NL &variables.NL &variables.NL &variables.NL &variables.NL &variables.NL );
			writeOutput('Invoice: ' & this.invoices[invoiceHeaderId].data.invoiceNumber);
		};	
	}	

	//Generate email template
	private function generateEmail(invoiceHeaderId){
		invoiceNumber = this.invoices[invoiceHeaderId].data.invoiceNumber;
		invoiceDate = dateFormat(this.invoices[invoiceHeaderId].data.invoiceDate,"mm/dd/yyyy");
		signature = this.invoices[invoiceHeaderId].data.signatureBlock;

		savecontent variable="emailBody" {
		writeOutput('<style>
				body{font-family: Arial, Helvetica, sans-serif;}

				div {clear: both;}
				.bold {font-weight: bolder;}
				##footer { font-size: .8em; }
				##control {font-size: .5em; }
			</style>

			<font face="Arial">
			<div id="salutation" font>Dear ECS Client,<br /><br /></div>
			<div id="intro">Thank you for Jones Media as your business partner. Attached is your most recent invoice.</div>
			<div id="invoiceDetail">
				<span class="bold">Invoice Number:</span> #invoiceNumber#<br />
				<span class="bold">Invoice Date:</span> #invoiceDate#
			</div>

			<br /><br />
			<div id="closing">If you have any questions or concerns that would result in delay of payment, please do not hesitate to contact me or reply to this email.</div>
			<br /><br />
			<div id="signOff">Thank you,</div>
			<br /><br />
			<div id="signatureBlock">
			#signature#
			</div>
			<br /><br />
			<div id="footer">
			A PDF viewer is required to view this file. To download a free reader from Adobe, click on the link: <a href="http://www.adobe.com/prodindex/acrobat/readstep.html">PDF Viewer</a>
			<br /><br />
			<em>Confidential/proprietary message/attachments. Delete message/attachments if not intended recipient.</em>
			</div>
			<div id="control">ControlNO:#invoiceNumber#</div>
			</font>');
		}
			
			return emailBody;
	}

	private function sendError(error, officeId, projectNumber){
		body = '<h2>An error occured trying to generate invoice PDFs for office ' & officeId & ' for project: ' & projectNumber& '</h2><br />';
		body &= error;

		mailObject = new mail();
		mailObject.setServer([server]);
		mailObject.setTo('jeff@jones-us.com');
		mailObject.setFrom('jeff@jones-us.com');
		mailObject.setSubject('An error occured trying to generate invoice PDFs for office ' & officeId);
		mailObject.setType('html');
		mailObject.send(body=body);
	}
}