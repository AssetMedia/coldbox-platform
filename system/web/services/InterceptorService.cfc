﻿<!-----------------------------------------------------------------------
********************************************************************************
Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldbox.org | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author     :	Luis Majano
Date        :	9/28/2007
Description :
	The interceptor service for all interception related methods.
----------------------------------------------------------------------->
<cfcomponent output="false" hint="The coldbox interceptor service" extends="coldbox.system.web.services.BaseService">

<!------------------------------------------- CONSTRUCTOR ------------------------------------------->

	<cffunction name="init" access="public" output="false" returntype="InterceptorService" hint="Constructor">
		<!--- ************************************************************* --->
		<cfargument name="controller" type="any" required="true">
		<!--- ************************************************************* --->
		<cfscript>
			// Register Controller
			setController( arguments.controller );
			
			// Register the interception points ENUM 
			instance.interceptionPoints = [ 
				// Application startup points
				"afterConfigurationLoad", "afterAspectsLoad", "preReinit",
				// On Actions
				"onException", "onRequestCapture", "onInvalidEvent",
				// After FW Object Creations
				"afterHandlerCreation", "afterInstanceCreation", "afterPluginCreation",
				// Life-cycle
				"applicationEnd" , "sessionStart", "sessionEnd", "preProcess", "preEvent", "postEvent", "postProcess", "preProxyResults",
				// Layout-View Events
				"preLayout", "preRender", "postRender", "preViewRender", "postViewRender",
				// Module Events
				"preModuleLoad", "postModuleLoad", "preModuleUnload", "postModuleUnload",
				// Debugger
				"beforeDebuggerPanel", "afterDebuggerPanel",
				// ORM Bridge Events
				"ORMPostNew", "ORMPreLoad", "ORMPostLoad", "ORMPostDelete", "ORMPreDelete", "ORMPreUpdate", "ORMPostUpdate", "ORMPreInsert", "ORMPostInsert", "ORMPreSave", "ORMPostSave" ];
				
			// Init Container of interception statues
			instance.interceptionStates = {};
			// Init the Request Buffer
			instance.requestBuffer = CreateObject("component","coldbox.system.core.util.RequestBuffer").init();
			// Default Logging
			instance.log = controller.getLogBox().getLogger( this );
    		// Setup Default Configuration
    		instance.interceptorConfig = {};
			
			return this;
		</cfscript>
	</cffunction>

<!------------------------------------------- INTERNAL COLDBOX EVENTS ------------------------------------------->
		
	<!--- onConfigurationLoad --->
    <cffunction name="onConfigurationLoad" output="false" access="public" returntype="void" hint="Called by loader service when configuration file loads">
    	<cfscript>
			// Reconfigure Logging
    		instance.log = controller.getLogBox().getLogger( this );
    		// Setup Configuration
    		instance.interceptorConfig = controller.getSetting("InterceptorConfig");
			// Register CFC Configuration Object
			registerInterceptor(interceptorObject=controller.getSetting('coldboxConfig'),interceptorName="coldboxConfig");
			// Register The Interceptors
			registerInterceptors();
    	</cfscript>
    </cffunction>

<!------------------------------------------- PUBLIC ------------------------------------------->

	<!--- Register All the interceptors --->
	<cffunction name="registerInterceptors" access="public" returntype="any" hint="Register all the interceptors according to configuration. All interception states are lazy loaded in." output="false" >
		<cfscript>
			var x = 1;
			
			// if simple, inflate
			if( isSimpleValue( instance.interceptorConfig.customInterceptionPoints ) ){
				instance.interceptorConfig.customInterceptionPoints = listToArray( instance.interceptorConfig.customInterceptionPoints );
			}
			
			// Check if we have custom interception points, and register them if we do
			if( arrayLen( instance.interceptorConfig.customInterceptionPoints ) ){
				appendInterceptionPoints( instance.interceptorConfig.customInterceptionPoints );
				
				if( instance.log.canDebug() ){
					instance.log.debug("Registering custom interception points: #instance.interceptorConfig.customInterceptionPoints.toString()#");
				}
			}
			
			// Loop over the Interceptor Array, to begin registration
			for (; x lte arrayLen(instance.interceptorConfig.interceptors); x=x+1){
				registerInterceptor(interceptorClass=instance.interceptorConfig.interceptors[x].class,
									interceptorProperties=instance.interceptorConfig.interceptors[x].properties,
									interceptorName=instance.interceptorConfig.interceptors[x].name);				
			}	
			
			return this;	
		</cfscript>
	</cffunction>

	<!--- Process a State's Interceptors --->
	<cffunction name="processState" access="public" returntype="any" hint="Process an interception state announcement" output="true">
		<!--- ************************************************************* --->
		<cfargument name="state" 		 required="true" 	type="any" hint="An interception state to process">
		<cfargument name="interceptData" required="false" 	type="any" default="#structNew()#" hint="A data structure used to pass intercepted information.">
		<!--- ************************************************************* --->
		<cfset var timerHash = 0><cfsilent>
		<cfscript>
		// Is ColdBox Inited and ready to serve requests?
		if ( NOT controller.getColdboxInitiated() ){ 
			return this;
		}
		
		// Validate Incoming State
		if ( instance.interceptorConfig.throwOnInvalidStates AND NOT listFindNoCase(arrayToList( instance.interceptionPoints ), arguments.state)){
			getUtil().throwit("The interception state sent in to process is not valid: #arguments.state#","Valid states are #instance.interceptionPoints.toString()#","InterceptorService.InvalidInterceptionState");
		}
		
		// Process The State if it exists, else just exit out
		if( structKeyExists(instance.interceptionStates, arguments.state) ){
			// Execute Interception
			timerHash = controller.getDebuggerService().timerStart("interception [#arguments.state#]");
			structFind( instance.interceptionStates, arguments.state).process(controller.getRequestService().getContext(),arguments.interceptData);
			controller.getDebuggerService().timerEnd(timerHash);
		}
		
		// Process Output Buffer: looks weird, but we are outputting stuff
		</cfscript>
		</cfsilent><!---
		---><cfif instance.requestBuffer.isBufferInScope()><!---
			---><cfset writeOutput(instance.requestBuffer.getString())><!---
			---><cfset instance.requestBuffer.clear()><!---
		---></cfif>
	</cffunction>
	
	<!--- Register an Interceptor --->
	<cffunction name="registerInterceptor" access="public" output="false" returntype="any" hint="Register an interceptor. This method is here for runtime additions. If the interceptor is already in a state, it will not be added again. You can register an interceptor by class or with an already instantiated and configured object.">
		<!--- ************************************************************* --->
		<cfargument name="interceptorClass" 		required="false" 	type="any" 		hint="Mutex with interceptorObject, this is the qualified class of the interceptor to register">
		<cfargument name="interceptorObject" 		required="false" 	type="any" 		hint="Mutex with interceptor Class, this is used to register an already instantiated object as an interceptor">
		<cfargument name="interceptorProperties" 	required="false" 	type="any"		default="#structNew()#" 	hint="The structure of properties to register this interceptor with." colddoc:generic="struct">
		<cfargument name="customPoints" 			required="false" 	type="any" 		default="" hint="A comma delimmited list or array of custom interception points, if the object or class sent in observes them.">
		<cfargument name="interceptorName" 			required="false"    type="any"   	hint="The name to use for the interceptor when stored. If not used, we will use the name found in the object's class"/>
		<!--- ************************************************************* --->
		<cfscript>
			var oInterceptor = "";
			var objectName = "";
			var objectKey = '';
			var interceptionPointsFound = structNew();
			var stateKey = "";
			var interceptData = structnew();			
		</cfscript>
		
		<!--- Determine Registration Name and set local interception object if sent --->
		<cfif structKeyExists(arguments,"interceptorClass") >
			<cfset objectName = listLast(arguments.interceptorClass,".")>
			<cfif structKeyExists(arguments,"interceptorName")>
				<cfset objectName = arguments.interceptorName>
			</cfif>
			<cfset objectKey = getColdboxOCM().INTERCEPTOR_CACHEKEY_PREFIX & objectName>
		<cfelseif structKeyExists(arguments,"interceptorObject")>
			<cfset objectName = listLast(getMetaData(arguments.interceptorObject).name,".")>
			<cfif structKeyExists(arguments,"interceptorName")>
				<cfset objectName = arguments.interceptorName>
			</cfif>			
			<cfset objectKey = getColdboxOCM().INTERCEPTOR_CACHEKEY_PREFIX & objectName>
			<cfset oInterceptor = arguments.interceptorObject>			
		<cfelse>
			<cfthrow message="Invalid registration" detail="You did not send in an interceptorClass or interceptorObject for registration" type="InterceptorService.InvalidRegistration">
		</cfif>
		
		<!--- Lock this registration --->
		<cflock name="interceptorService.registerInterceptor.#objectName#" type="exclusive" throwontimeout="true" timeout="30">
			<cfscript>
				// Did we send in a class to instantiate
				if( structKeyExists(arguments,"interceptorClass") ){
					// Create the Interceptor Class
					try{
						oInterceptor = createInterceptor(arguments.interceptorClass, arguments.interceptorProperties);
					}
					catch(Any e){
						instance.log.error("Error creating interceptor: #arguments.interceptorClass#. #e.detail# #e.message# #e.stackTrace#",e.tagContext);
						getUtil().rethrowit(e);
					}
					
					// Configure the Interceptor
					oInterceptor.configure();
					
					// Cache The Interceptor for quick references
					if ( NOT getColdBoxOCM().set(objectKey, oInterceptor, 0) ){
						getUtil().throwit("The interceptor could not be cached, either the cache is full, the threshold has been reached or we are out of memory.","Please check your cache limits, try increasing them or verify your server memory","InterceptorService.InterceptorCantBeCached");
					}
					
				}//end if class is sent.
				
				// Append Custom Points
				appendInterceptionPoints( arguments.customPoints );
				
				// Parse Interception Points, thanks to inheritance.
				interceptionPointsFound = structnew();
				interceptionPointsFound = parseMetadata( getMetaData(oInterceptor), interceptionPointsFound);
				
				// Register this Interceptor's interception point with its appropriate interceptor state
				for(stateKey in interceptionPointsFound){
					registerInterceptionPoint(objectKey,stateKey,oInterceptor);
					if( instance.log.canDebug() ){
						instance.log.debug("Registering #objectName# on '#statekey#' interception point ");
					}
				}
				
				// Autowire this interceptor only if called after aspect registration
				if( controller.getAspectsInitiated() ){
					controller.getWireBox().autowire(target=oInterceptor,targetID=objectKey);
				}			
			</cfscript>
		</cflock>
		
		<cfreturn this>
	</cffunction>
	
	<!--- createInterceptor --->
    <cffunction name="createInterceptor" output="false" access="private" returntype="any" hint="Create an interceptor object">
    	<cfargument name="interceptorClass" 	 required="true" hint="The class Path to instantiate"/>
		<cfargument name="interceptorProperties" required="false" default="#structnew()#" hint="The properties" colddoc:generic="struct"/>
		<cfscript>
    		var oInterceptor 	= createObject("component", arguments.interceptorClass );
			var baseInterceptor = "";
			var key 			= "";
			
			// Check family if it is interceptor inheritance or simple CFC?
			if( NOT isFamilyType("interceptor",oInterceptor) ){
				convertToColdBox( "interceptor", oInterceptor );
				// Init super
				oInterceptor.$super.init( controller, arguments.interceptorProperties);
			}
			
			return	oInterceptor.init(controller,arguments.interceptorProperties);
		</cfscript>
    </cffunction>
	
	<!--- Get Interceptor --->
	<cffunction name="getInterceptor" access="public" output="false" returntype="any" hint="Get an interceptor according to its name from cache, not from a state. If retrieved, it does not mean that the interceptor is registered still. It just means, that it is in cache. Use the deepSearch argument if you want to check all the interception states for the interceptor.">
		<!--- ************************************************************* --->
		<cfargument name="interceptorName" 	required="false" type="string" hint="The name of the interceptor to search for"/>
		<cfargument name="deepSearch" 		required="false" type="boolean" default="false" hint="By default we search the cache for the interceptor reference. If true, we search all the registered interceptor states for a match."/>
		<!--- ************************************************************* --->
		<cfscript>
			var interceptorKey = getColdboxOCM().INTERCEPTOR_CACHEKEY_PREFIX & arguments.interceptorName;
			var states = getInterceptionStates();
			var state = "";
			var key = "";
			
			if( arguments.deepSearch ){
				for( key in states ){
					state = states[key];
					if( state.exists(interceptorKey) ){ return state.getInterceptor(interceptorKey); }
				}
				// Throw Exception
				getUtil().throwit(message="Interceptor: #arguments.interceptorName# not found in any state: #structKeyList(states)#.",
					  			  type="InterceptorService.InterceptorNotFound");
			}
			
			// ELSE Cache Lookup
			// Verify it exists else throw error
			if( not getColdboxOCM().lookup(interceptorKey) ){
				getUtil().throwit(message="Interceptor: #arguments.interceptorName# not found in cache.",
					  			  type="InterceptorService.InterceptorNotFound");
			}
			
			return getColdboxOCM().get(interceptorKey);
		</cfscript>
	</cffunction>
	
	<!--- Append Interception Points --->
	<cffunction name="appendInterceptionPoints" access="public" returntype="any" hint="Append a list of custom interception points to the CORE interception points and returns itself" output="false" >
		<cfargument name="customPoints" required="true" type="any" hint="A comma delimmited list or array of custom interception points to append. If they already exists, then they will not be added again.">
		<cfscript>
			var x 			= 1;
			var currentList = arrayToList( instance.interceptionPoints );
			
			// Inflate custom points
			if( isSimpleValue( arguments.customPoints ) ){
				arguments.customPoints = listToArray( arguments.customPoints );
			}
			
			// Validate customPoints or just return yourself
			if( arrayLen( arguments.customPoints ) EQ 0 ){ return this; }
			
			// Loop and Add custom points
			for(; x LTE arrayLen(arguments.customPoints); x++ ){
				// add only if not found
				if ( NOT listfindnocase( currentList, arguments.customPoints[x] ) ){
					// Add to both lists
					currentList = listAppend(currentList, arguments.customPoints[x] );
					arrayAppend( instance.interceptionPoints, arguments.customPoints[x] );
				}				
			}	
		</cfscript>
	</cffunction>
	
	<!--- getter interceptionPoints --->
	<cffunction name="getInterceptionPoints" access="public" output="false" returntype="any" hint="Get the interceptionPoints ENUM of all registered points of execution as an array" colddoc:generic="array">
		<cfreturn instance.interceptionPoints/>
	</cffunction>

	<!--- getter interception states --->
	<cffunction name="getInterceptionStates" access="public" output="false" returntype="any" hint="Get all the interception states defined in this service" colddoc:generic="struct">
		<cfreturn instance.interceptionStates/>
	</cffunction>
	
	<!--- getter request buffer --->
	<cffunction name="getRequestBuffer" access="public" returntype="any" output="false" hint="Get a coldbox request buffer: coldbox.system.core.util.RequestBuffer">
		<cfreturn instance.RequestBuffer>
	</cffunction>
	
	<!--- Get State Container --->
	<cffunction name="getStateContainer" access="public" returntype="any" hint="Get a State Container, it will return a blank structure if the state is not found." output="false" >
		<cfargument name="state" required="true" hint="The state name to retrieve">
		<cfscript>
			var states = getInterceptionStates();
			
			if( structKeyExists(states,arguments.state) ){
				return states[arguments.state];
			}
			
			return structnew();
		</cfscript>
	</cffunction>
	
	<!--- Unregister From a State --->
	<cffunction name="unregister" access="public" returntype="boolean" hint="Unregister an interceptor from an interception state or all states. If the state does not exists, it returns false" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="interceptorName" 	required="true" hint="The name of the interceptor to search for"/>
		<cfargument name="state" 			required="false" default="" hint="The named state to unregister this interceptor from. If not passed, then it will be unregistered from all states.">
		<!--- ************************************************************* --->
		<cfscript>
			var states 		 = instance.interceptionStates;
			var unregistered = false;
			var key 		 = "";
			var keyPrefix    = getColdboxOCM().INTERCEPTOR_CACHEKEY_PREFIX;
			
			// Else, unregister from all states
			for(key in states){
				
				if( len(trim(arguments.state)) eq 0 OR trim(arguments.state) eq key ){
					structFind(states,key).unregister(keyPrefix & arguments.interceptorName);
					unregistered = true;
				}
								
			}
			
			return unregistered;						
		</cfscript>
	</cffunction>

<!------------------------------------------- PRIVATE ------------------------------------------->
	
	<!--- Get an interceptors interception points via metadata --->
	<cffunction name="parseMetadata" returntype="struct" access="private" output="false" hint="I get a components valid interception points">
		<!--- ************************************************************* --->
		<cfargument name="metadata" required="true" type="any" 		hint="The recursive metadata">
		<cfargument name="points" 	required="true" type="struct" 	hint="The active points">
		<!--- ************************************************************* --->
		<cfscript>
			var x 			= 1;
			var pointsFound = arguments.points;
			var currentList = arrayToList( instance.interceptionPoints );
			
			// Register local functions		
			if( structKeyExists(arguments.metadata, "functions") ){
				
				for(x=1; x lte ArrayLen(arguments.metadata.functions); x=x+1 ){
					
					// Verify the @interceptionPoint annotation
					if( structKeyExists(arguments.metadata.functions[x],"interceptionPoint") ){
						// Register the point by convention and annotation
						appendInterceptionPoints( arguments.metadata.functions[x].name );
					}
					
					// verify its a plugin point by comparing it to the local defined interception points
					if ( listFindNoCase( currentList, arguments.metadata.functions[x].name ) AND 
						 NOT structKeyExists( pointsFound, arguments.metadata.functions[x].name ) ){
						// Insert to metadata struct of points found
						structInsert( pointsFound, arguments.metadata.functions[x].name, true );			
					}
					
				}// loop over functions
			}
			
			// Start Registering inheritances
			if ( structKeyExists(arguments.metadata, "extends") and 
				 (arguments.metadata.extends.name neq "coldbox.system.Interceptor" and
				  arguments.metadata.extends.name neq "coldbox.system.Plugin" and
				  arguments.metadata.extends.name neq "coldbox.system.EventHandler" )
			){
				// Recursive lookup
				parseMetadata( arguments.metadata.extends, pointsFound );
			}
			//return the interception points found
			return pointsFound;
		</cfscript>	
	</cffunction>
	
	<!--- Register an Interception Point --->
	<cffunction name="registerInterceptionPoint" access="private" returntype="void" hint="Register an Interception point into a new or created interception state." output="false" >
		<!--- ************************************************************* --->
		<cfargument name="interceptorKey" 	required="true" type="any" hint="The interceptor key in the cache.">
		<cfargument name="state" 			required="true" type="any" hint="The state to create">
		<cfargument name="oInterceptor" 	required="true" type="any" hint="The interceptor to register">
		<!--- ************************************************************* --->
		<cfscript>
			var oInterceptorState = "";
			
			// Verify if state doesn't exist, create it
			if ( NOT structKeyExists( instance.interceptionStates, arguments.state ) ){
				oInterceptorState = CreateObject("component","coldbox.system.web.context.InterceptorState").init( arguments.state );
				structInsert( instance.interceptionStates , arguments.state, oInterceptorState );
			}
			else{
				// Get the State we need to register in
				oInterceptorState = structFind( instance.interceptionStates, arguments.state );
			}
			
			// Verify if the interceptor is already in the state
			if( NOT oInterceptorState.exists( arguments.interceptorKey ) ){
				//Register it
				oInterceptorState.register( arguments.interceptorKey, arguments.oInterceptor );	
			}	
		</cfscript>
	</cffunction>

</cfcomponent>