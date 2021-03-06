/*
GnuCash MySql routines
Author : Adam Harrington
Date : 5 September 2018
*/

-- Customgnucash actions below are marked [R] if they require Readonly access to the gnucash database, [W] Writeonly and [RW] for both.
-- If you have no intention of using [W] procedures, then customgnucash only requires read access to the gnucash database.
-- Adding or changing data in the gnucash database outside the GnuCash application is not supported; be aware of the risk!
-- Specifically, the GnuCash client GUI won't be aware of changes made this way until it is restarted.
-- There is a locking mechanism built into Customgnucash to help with this.

-- Limitations
-- This set of routines was intended as a 'toolbox' of useful functions; consequently it sometimes sacrifices efficiency for reuseability
-- Adding a few indices to the Gnucash db (see below) helps a little

-- Safety
-- A non-GnuCash database should be used (such as 'customgnucash')
-- - we want to minimise interference with default GnuCash behaviour or upgrade paths
-- the customgnucash database and its routines should be accessed by a specified user (such as 'customgnucash')
-- - this means we can control access to the real gnucash db
-- you can turn off all routines that amend gnucash data by telling customgnucash that gnucash is readonly :
-- SQL> call put_variable('Gnucash status', 'R')

-- BEFORE RUNNNG THIS SCRIPT
-- you need to set up the database and appropriate users ('<..>' indicates a value you need to find out for yourself). Example :

-- LINUX> mysql --user=<super user> --password=<super user password>
-- SQL> create schema if not exists customgnucash;
-- SQL> create user 'customgnucash'@'localhost' IDENTIFIED BY 'customgnucash'; 
-- SQL> grant all on customgnucash.* to 'customgnucash'@'localhost';
-- SQL> grant select on gnucash.* to 'customgnucash'@'localhost'; -- if you DON'T want to allow customgnucash to change gnucash data
-- SQL> grant select, insert, update, delete on gnucash.* to 'customgnucash'@'localhost'; -- if you DO want to allow customgnucash to change gnucash data
-- SQL> quit;

-- OPTIONAL PERFORMANCE IMPROVEMENTS TO GNUCASH DATABASE
-- these are entirely optional and may be lost in a Gnucash upgrade

-- LINUX> mysql --user=<super user> --password=<super user password>
-- SQL> use gnucash;
-- SQL> alter table gnucash.accounts 		add index(commodity_guid), 	add index(parent_guid), 	add index(account_type);
-- SQL> alter table gnucash.commodities 	add index(fullname), 		add index(namespace), 		add index(mnemonic), 	add index(quote_flag);
-- SQL> alter table gnucash.prices 		add index(commodity_guid), 	add index(date);
-- SQL> alter table gnucash.slots 		add index(obj_guid), 		add index(name);
-- SQL> alter table gnucash.splits 		add index(tx_guid), 		add index(account_guid), 	add index(value_num), 	add index(quantity_num);
-- SQL> alter table gnucash.transactions 	add index(post_date), 		add index(currency_guid);

-- FROM THIS POINT ON 
-- it is recommended this script is run by a limited (non super-) user such as 'customgnucash' that has no DDL access to the gnucash db:

-- LINUX> mysql --user=customgnucash --password=<customgnucash password> --database=customgnucash < CustomGnucash.sql

-- SCRIPT STARTS HERE

-- Optionally hard-code this script
-- use customgnucash;

-- database flags (may need super user privileges to run)
-- set sql_mode=ansi;
-- PIPES_AS_CONCAT ('something' || 'something else') it only used when create log messages; concat('something','something else') is more standard
-- set sql_mode=PIPES_AS_CONCAT;
-- set global group_concat_max_len=60000; -- required to allow group_concat to list up to 800 account guids

-- mandatorily set delimiter (otherwise MySQL/MariaDB parser throws a fit when parsing multiline procedures)
delimiter //

-- PROTOTYPES
-- These dummy (stubbed) functions and procedures are created in advance to ensure the remaining script compiles irrespective of the order of create commands
-- list initially created by :
/*
select routines.command from
(
select 
 concat( 'drop ', routine_type, ' if exists ', specific_name, '; //' ) as command,
 routine_type,
 specific_name
from
 information_schema.routines 
where
 routine_schema = 'customgnucash' 
union
 select concat( 'create ', routine_type, '  ', specific_name, '() returns boolean begin return false; end; //' ),
 routine_type,
 specific_name
from
 information_schema.routines 
where
 routine_schema = 'customgnucash' 
 and routine_type = 'FUNCTION'
union
 select concat( 'create ', routine_type, '  ', specific_name, '() begin end; //' ),
 routine_type,
 specific_name
from
 information_schema.routines 
where
 routine_schema = 'customgnucash' 
 and routine_type = 'PROCEDURE'
) routines;
*/
 drop PROCEDURE if exists clean_prices; //
 drop PROCEDURE if exists clean_commodities; //                                             
 drop PROCEDURE if exists customgnucash_status; //                                          
 drop PROCEDURE if exists delete_commodity_attribute; //                                    
 drop PROCEDURE if exists delete_derived_commodity_attributes; //                           
 drop PROCEDURE if exists delete_variable; //                                               
 drop FUNCTION if exists convert_value; //                                                  
 drop PROCEDURE if exists delete_series; //                                                 
 drop FUNCTION if exists exists_account; //                                                 
 drop FUNCTION if exists exists_commodity; //                                               
 drop FUNCTION if exists exists_commodity_attribute; //                                     
 drop FUNCTION if exists exists_price; //                                                   
 drop FUNCTION if exists exists_variable; //                                                
 drop FUNCTION if exists get_account_commodity; //                                          
 drop PROCEDURE if exists get_account_costs; //                                             
 drop FUNCTION if exists get_account_currency; //                                           
 drop FUNCTION if exists exists_split; //                                                   
 drop FUNCTION if exists exists_transaction; //                                             
 drop FUNCTION if exists get_account_attribute; //                                          
 drop FUNCTION if exists get_account_children; //                                           
 drop FUNCTION if exists get_account_guid; //                                               
 drop FUNCTION if exists get_account_long_name; //                                          
 drop FUNCTION if exists get_account_root; //                                               
 drop FUNCTION if exists get_account_short_name; //                                         
 drop FUNCTION if exists get_account_parents; //                                            
 drop FUNCTION if exists get_account_type; //                                               
 drop FUNCTION if exists get_account_units; //                                              
 drop FUNCTION if exists get_account_value; //                                              
 drop FUNCTION if exists get_commodity_attribute; //                                        
 drop FUNCTION if exists get_commodity_currency; //                                         
 drop FUNCTION if exists get_commodity_guid; //                                             
 drop FUNCTION if exists get_commodity_latest_denom; //                                     
 drop FUNCTION if exists get_commodity_mnemonic; //                                         
 drop FUNCTION if exists get_commodity_earliest_date; //                                    
 drop FUNCTION if exists get_commodity_ema; //                                              
 drop FUNCTION if exists get_commodity_extreme_price; //        
 drop FUNCTION if exists get_commodity_extreme_date; //                                       
 drop FUNCTION if exists get_commodity_latest_date; //                                      
 drop FUNCTION if exists get_commodity_name; //                                             
 drop FUNCTION if exists get_commodity_namespace; //                                        
 drop FUNCTION if exists get_default_currency_guid; //                                      
 drop FUNCTION if exists get_element; //                                                    
 drop FUNCTION if exists get_commodity_performance; //                                      
 drop PROCEDURE if exists get_commodity_ppo; //                                             
 drop FUNCTION if exists get_element_count; //                                              
 drop FUNCTION if exists get_tax_year_end; //                                               
 drop FUNCTION if exists get_commodity_price; //                                            
 drop FUNCTION if exists get_commodity_sma; //                                                                                                                                    
 drop FUNCTION if exists get_transaction_accounts; //                                       
 drop PROCEDURE if exists get_commodity_so; //                                              
 drop FUNCTION if exists get_variable; //    
 drop FUNCTION if exists get_variable_date; //    
 drop FUNCTION if exists get_constant; //                                              
 drop FUNCTION if exists html_bar; //                                                       
 drop FUNCTION if exists is_child; //                                                       
 drop FUNCTION if exists is_child_of; //                                                    
 drop FUNCTION if exists is_currency; //                                                                                                 
 drop FUNCTION if exists get_related_account; //                                            
 drop PROCEDURE if exists get_report; //                                                    
 drop FUNCTION if exists is_guid; //                                                        
 drop FUNCTION if exists is_hidden; //                                                      
 drop FUNCTION if exists is_number; //                                                      
 drop FUNCTION if exists is_parent; //                                                      
 drop FUNCTION if exists is_placeholder; //                                                 
 drop PROCEDURE if exists get_series; //                                                    
 drop FUNCTION if exists get_signal; //                                                
 drop FUNCTION if exists get_transactions_value; //        
 drop FUNCTION if exists get_transaction_date; //                                    
 drop FUNCTION if exists is_used; //                                                        
 drop PROCEDURE if exists log; //                                                           
 drop FUNCTION if exists new_guid; //                                                       
 drop PROCEDURE if exists post_commodity_attribute; //                                      
 drop PROCEDURE if exists post_variable; //                                                 
 drop FUNCTION if exists gnc_lock; //                                                       
 drop PROCEDURE if exists gnc_unlock; //                                                    
 drop FUNCTION if exists prettify; //    
 drop FUNCTION if exists pluralise; //                                                       
 drop PROCEDURE if exists put_commodity_attribute; //                                       
 drop PROCEDURE if exists put_element; //                                                   
 drop PROCEDURE if exists put_variable; //                                                  
 drop PROCEDURE if exists report_account_gains; //                                          
 drop FUNCTION if exists is_locked; //                                                      
 drop FUNCTION if exists post_account; //                                                   
 drop PROCEDURE if exists post_all_gains; //                                                
 drop PROCEDURE if exists report_target_allocations; //                                     
 drop PROCEDURE if exists report_uk_tax; //                                                 
 drop FUNCTION if exists round_timestamp; //                                                
 drop FUNCTION if exists post_commodity; //                                                 
 drop FUNCTION if exists post_commodity_price; //                                           
 drop FUNCTION if exists post_dividend; //                                                  
 drop PROCEDURE if exists report_anomalies; //                                              
 drop FUNCTION if exists post_gain; //                                                      
 drop FUNCTION if exists post_split; //                                                     
 drop PROCEDURE if exists report_asset_allocation; //                                       
 drop PROCEDURE if exists report_remaining_isa_allowance; //                                
 drop PROCEDURE if exists reschedule; //  
 drop PROCEDURE if exists run_schedule; //                                                    
 drop FUNCTION if exists sort_array; //                                                     
 drop PROCEDURE if exists write_report; //                                                  
 create FUNCTION  convert_value() returns boolean no sql  begin return false; end; //               
 create FUNCTION  exists_account() returns boolean no sql  begin return false; end; //              
 create FUNCTION  exists_commodity() returns boolean no sql  begin return false; end; //            
 create FUNCTION  exists_commodity_attribute() returns boolean no sql  begin return false; end; //  
 create FUNCTION  exists_price() returns boolean no sql  begin return false; end; //                
 create FUNCTION  exists_variable() returns boolean no sql  begin return false; end; //             
 create FUNCTION  get_account_commodity() returns boolean no sql  begin return false; end; //       
 create FUNCTION  get_account_currency() returns boolean no sql  begin return false; end; //        
 create FUNCTION  exists_split() returns boolean no sql  begin return false; end; //                
 create FUNCTION  exists_transaction() returns boolean no sql  begin return false; end; //          
 create FUNCTION  get_account_attribute() returns boolean no sql  begin return false; end; //       
 create FUNCTION  get_account_children() returns boolean no sql  begin return false; end; //        
 create FUNCTION  get_account_guid() returns boolean no sql  begin return false; end; //            
 create FUNCTION  get_account_long_name() returns boolean no sql  begin return false; end; //       
 create FUNCTION  get_account_root() returns boolean no sql  begin return false; end; //            
 create FUNCTION  get_account_short_name() returns boolean no sql  begin return false; end; //      
 create FUNCTION  get_account_parents() returns boolean no sql  begin return false; end; //         
 create FUNCTION  get_account_type() returns boolean no sql  begin return false; end; //            
 create FUNCTION  get_account_units() returns boolean no sql  begin return false; end; //           
 create FUNCTION  get_account_value() returns boolean no sql  begin return false; end; //           
 create FUNCTION  get_commodity_attribute() returns boolean no sql  begin return false; end; //     
 create FUNCTION  get_commodity_currency() returns boolean no sql  begin return false; end; //      
 create FUNCTION  get_commodity_guid() returns boolean no sql  begin return false; end; //          
 create FUNCTION  get_commodity_latest_denom() returns boolean no sql  begin return false; end; //  
 create FUNCTION  get_commodity_mnemonic() returns boolean no sql  begin return false; end; //      
 create FUNCTION  get_commodity_earliest_date() returns boolean no sql  begin return false; end; // 
 create FUNCTION  get_commodity_ema() returns boolean no sql  begin return false; end; //           
 create FUNCTION  get_commodity_extreme_price() returns boolean no sql  begin return false; end; //    
 create FUNCTION  get_commodity_extreme_date() returns boolean no sql  begin return false; end; //      
 create FUNCTION  get_commodity_latest_date() returns boolean no sql  begin return false; end; //   
 create FUNCTION  get_commodity_name() returns boolean no sql  begin return false; end; //          
 create FUNCTION  get_commodity_namespace() returns boolean no sql  begin return false; end; //     
 create FUNCTION  get_default_currency_guid() returns boolean no sql  begin return false; end; //   
 create FUNCTION  get_element() returns boolean no sql  begin return false; end; //                 
 create FUNCTION  get_commodity_performance() returns boolean no sql  begin return false; end; //   
 create FUNCTION  get_element_count() returns boolean no sql  begin return false; end; //           
 create FUNCTION  get_tax_year_end() returns boolean no sql  begin return false; end; //            
 create FUNCTION  get_commodity_price() returns boolean no sql  begin return false; end; //         
 create FUNCTION  get_commodity_sma() returns boolean no sql  begin return false; end; //                            
 create FUNCTION  get_transaction_accounts() returns boolean no sql  begin return false; end; //    
 create FUNCTION  get_variable() returns boolean no sql  begin return false; end; //
 create FUNCTION  get_variable_date() returns boolean no sql  begin return false; end; //
 create FUNCTION  get_constant() returns boolean no sql  begin return false; end; //           
 create FUNCTION  html_bar() returns boolean no sql  begin return false; end; //                    
 create FUNCTION  is_child() returns boolean no sql  begin return false; end; //                    
 create FUNCTION  is_child_of() returns boolean no sql  begin return false; end; //                 
 create FUNCTION  is_currency() returns boolean no sql  begin return false; end; //                             
 create FUNCTION  get_related_account() returns boolean no sql  begin return false; end; //         
 create FUNCTION  is_guid() returns boolean no sql  begin return false; end; //                     
 create FUNCTION  is_hidden() returns boolean no sql  begin return false; end; //                   
 create FUNCTION  is_number() returns boolean no sql  begin return false; end; //                   
 create FUNCTION  is_parent() returns boolean no sql  begin return false; end; //                   
 create FUNCTION  is_placeholder() returns boolean no sql  begin return false; end; //              
 create FUNCTION  get_signal() returns boolean no sql  begin return false; end; //               
 create FUNCTION  get_transactions_value() returns boolean no sql  begin return false; end; //      
 create FUNCTION  get_transaction_date() returns boolean no sql  begin return false; end; //  
 create FUNCTION  is_used() returns boolean no sql  begin return false; end; //                     
 create FUNCTION  new_guid() returns boolean no sql  begin return false; end; //                    
 create FUNCTION  gnc_lock() returns boolean no sql  begin return false; end; //                    
 create FUNCTION  prettify() returns boolean no sql  begin return false; end; // 
 create FUNCTION  pluralise() returns boolean no sql  begin return false; end; //                    
 create FUNCTION  is_locked() returns boolean no sql  begin return false; end; //                   
 create FUNCTION  post_account() returns boolean no sql  begin return false; end; //                
 create FUNCTION  round_timestamp() returns boolean no sql  begin return false; end; //             
 create FUNCTION  post_commodity() returns boolean no sql  begin return false; end; //              
 create FUNCTION  post_commodity_price() returns boolean no sql  begin return false; end; //        
 create FUNCTION  post_dividend() returns boolean no sql  begin return false; end; //               
 create FUNCTION  post_gain() returns boolean no sql  begin return false; end; //                   
 create FUNCTION  post_split() returns boolean no sql  begin return false; end; //                  
 create FUNCTION  sort_array() returns boolean no sql  begin return false; end; //                  
 create PROCEDURE  clean_prices() no sql begin end; //  
 create PROCEDURE  clean_commodities() no sql begin end; //                                             
 create PROCEDURE  customgnucash_status() no sql begin end; //                                     
 create PROCEDURE  delete_commodity_attribute() no sql begin end; //                               
 create PROCEDURE  delete_derived_commodity_attributes() no sql begin end; //                      
 create PROCEDURE  delete_variable() no sql begin end; //                                          
 create PROCEDURE  delete_series() no sql begin end; //                                            
 create PROCEDURE  get_account_costs() no sql begin end; //                                        
 create PROCEDURE  get_commodity_ppo() no sql begin end; //                                        
 create PROCEDURE  get_commodity_so() no sql begin end; //                                         
 create PROCEDURE  get_report() no sql begin end; //                                               
 create PROCEDURE  get_series() no sql begin end; //                                               
 create PROCEDURE  log() no sql begin end; //                                                      
 create PROCEDURE  post_commodity_attribute() no sql begin end; //                                 
 create PROCEDURE  post_variable() no sql begin end; //                                            
 create PROCEDURE  gnc_unlock() no sql begin end; //                                               
 create PROCEDURE  put_commodity_attribute() no sql begin end; //                                  
 create PROCEDURE  put_element() no sql begin end; //                                              
 create PROCEDURE  put_variable() no sql begin end; //                                             
 create PROCEDURE  report_account_gains() no sql begin end; //                                     
 create PROCEDURE  post_all_gains() no sql begin end; //                                           
 create PROCEDURE  report_target_allocations() no sql begin end; //                                
 create PROCEDURE  report_uk_tax() no sql begin end; //                                            
 create PROCEDURE  report_anomalies() no sql begin end; //                                         
 create PROCEDURE  report_asset_allocation() no sql begin end; //                                  
 create PROCEDURE  report_remaining_isa_allowance() no sql begin end; //                           
 create PROCEDURE  reschedule() no sql begin end; //            
 create PROCEDURE  run_schedule() no sql begin end; //                                        
 create PROCEDURE  write_report() no sql begin end; // 

-- [A] REQUIRED CUSTOM TABLES AND TRIGGERS TO THOSE TABLES

-- [A.1] Logging table

-- useful (but not critical) to keep, so leave the following drop line commented out if you can
-- xdrop table if exists log;
-- //
create table if not exists log (
	id 		int 		not null auto_increment,
	logdate 	timestamp 	null default null, -- "default current_timestamp" only returns the date the calling function was started, not the date the log was made
	log 		text		character set utf8,
	primary key (id)
);
//
set @table_count = ifnull(@table_count,0) + 1;
//

-- makes sure log date is accurate
drop trigger if exists log_logdate;
//
create trigger log_logdate 
	before insert on log
	for each row
procedure_block : begin
	set new.logdate = sysdate();
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

-- [A.2] User-defined global variables table

-- useful (but not critical) to keep, so leave the following drop line commented out if you can
-- xdrop table if exists variable;
-- //
create table if not exists variable (
	variable 	varchar(250) 	character set utf8 not null,
	value 		text		character set utf8,
	logdate 	timestamp 	null default null,
	primary key (variable)
);
//
set @table_count = ifnull(@table_count,0) + 1;
//

-- makes sure log date is accurate
drop trigger if exists variable_logdate_insert;
//
create trigger variable_logdate_insert 
	before insert on variable
	for each row
procedure_block : begin
	set new.logdate = sysdate();
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

drop trigger if exists variable_logdate_update;
//
create trigger variable_logdate_update 
	before update on variable
	for each row
procedure_block : begin
	set new.logdate = sysdate();
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

-- [A.3] Extension to the gnucash.prices table

-- gnucash only holds commodity prices; if we want to hold dividends, PE ratios, volumes etc, we put them here
-- some of this data may be difficult to recreate if the table was lost
-- xdrop table if exists commodity_attribute;
-- //
create table if not exists commodity_attribute (
	id 		int 		not null auto_increment,
	commodity_guid	varchar(32)	character set utf8 not null,
	field		varchar(100)	character set utf8 not null,
	value_date	timestamp	null,
	value 		text		character set utf8 not null,
	logdate 	timestamp 	null default null,
	primary key (id),
	unique key guid_field_date_indx (commodity_guid, field, value_date),
	index commodity_guid_indx (commodity_guid),
	index field_indx (field),
	index value_date_indx (value_date)
);
//
set @table_count = ifnull(@table_count,0) + 1;
//

-- makes sure log date is accurate
drop trigger if exists commodity_attribute_logdate_insert;
//
create trigger commodity_attribute_logdate_insert 
	before insert on commodity_attribute
	for each row
procedure_block : begin
	set new.logdate = sysdate();
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

drop trigger if exists commodity_attribute_logdate_update;
//
create trigger commodity_attribute_logdate_update 
	before update on commodity_attribute
	for each row
procedure_block : begin
	set new.logdate = sysdate();
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

-- [RW] Propagates prices from customgnucash.commodity_attribute (whither they are put by an OS routine using perl Finance::Quote) and loads them into gnucash.prices
-- also propagates dividends into applicable accounts
drop trigger if exists propagate_commodity_attribute;
//
create trigger propagate_commodity_attribute 
	after insert on commodity_attribute
	for each row
procedure_block : begin

	-- call log('DEBUG : START propagate_commodity_attribute');

	if 	datediff(current_timestamp, new.value_date) >= 0
		and is_number(new.value)
	then

		-- propagate a new price for the appropriate gnucash commodity
		if 	lower(new.field) in ('last', 'price')
		-- and	get_commodity_price(new.commodity_guid, new.value_date) != convert(new.value, decimal(15,5))
		then
			do post_commodity_price(	
					new.commodity_guid,
					new.value_date,
					if( 	is_currency(new.commodity_guid),
						get_default_currency_guid(),
						ifnull(	get_commodity_guid( get_commodity_attribute(new.commodity_guid, 'currency', new.value_date) ),
							get_commodity_currency( new.commodity_guid)
						)
					),
					convert(new.value, decimal(20,6)),
					ifnull(get_commodity_attribute(new.commodity_guid, 'method', new.value_date), 'Finance::Quote')
				);
		end if;

		-- propagate a new dividend into the appropriate gnucash account
		if lower(new.field) in ('div', 'dividend')
		then
			dividend_block : begin

			declare l_dividend_account_done 	boolean default false;
			declare l_dividend_account_done_temp	boolean default false;
			declare l_account_guid			varchar(32);

			-- list of accounts that use the commodity
			declare lc_dividend_account cursor for
				select
					accounts.guid
				from
					accounts
					join commodities on accounts.commodity_guid = commodities.guid
				where
					get_account_units(accounts.guid, null, null) > 0
					and get_account_type(accounts.guid) in ('STOCK', 'ASSET')
					and commodities.guid = new.commodity_guid;
			declare continue handler for not found set l_dividend_account_done = true;

			open lc_dividend_account;	
			set l_dividend_account_done = false;
	
			-- for each account using the commodity ...
			dividend_loop : loop
	
				fetch lc_dividend_account into l_account_guid;
	
				if l_dividend_account_done then 
					leave dividend_loop;
				else
					set l_dividend_account_done_temp = l_dividend_account_done;
				end if;

				if ifnull( convert(new.value, decimal(20,6)), 0) > 0 then
					do post_dividend(
						l_account_guid, 
						convert(new.value, decimal(20,6)), 
						new.value_date
					);	
				end if;

				set l_dividend_account_done = l_dividend_account_done_temp;
	
			end loop; -- dividend_loop

			close lc_dividend_account;	

			end; -- dividend_block
		end if;

	end if;

	-- call log('DEBUG : END propagate_commodity_attribute');
end;
//
set @trigger_count = ifnull(@trigger_count,0) + 1;
//

-- [B] UTILITY ROUTINES

-- [B.1] Logging routines

-- Adds a line to the log table (used mainly for debugging, but also used to log CustomGnucash updates to the Gnucash database)
drop procedure if exists log;
//
create procedure log
	(
		p_value		text
	)
procedure_block : begin

	declare l_value		text default null;

	-- have to do this manually rather than call get_variable otherwise you get recursion
	select 	distinct upper(value)
	into 	l_value
	from 	variable
	where 	upper(variable) = 'DEBUG';
	
	-- only log debug messages in debug mode
	if 	locate('DEBUG', p_value) > 0
		and l_value != 'Y'
	then
		leave procedure_block;
	end if;

	-- dump to customgnucash.log table
	insert into log (log)
	values (p_value);
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [B.2] User defined variable management routines

-- returns true if requested variable exists in customgnucash.variables
drop function if exists exists_variable;
//
create function exists_variable
	(
		p_variable 	varchar(250)
	)
	returns boolean
begin
	declare l_exists	boolean default null;

	-- call log( concat('DEBUG : START exists_variable(', ifnull(p_variable, 'null'), ')'));

	-- if not is_locked('variable', 'WAIT') then

		select 	SQL_NO_CACHE if(count(variable) > 0, true, false)
		into 	l_exists
		from 	variable
		where 	variable = trim(p_variable);

	-- end if;

	-- call log('DEBUG : END exists_variable');

	return l_exists;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns value associated with variable in customgnucash.variables
-- use when variable value might change between calls
drop function if exists get_variable;
//
create function get_variable
	(
		p_variable 	varchar(250)
	)
	returns text
begin
	declare l_value text default null;

	-- call log( concat('DEBUG : START get_variable(', ifnull(p_variable, 'null'), ')'));
	
	if 	exists_variable( p_variable) 
	--	and not is_locked('variable', 'WAIT')
	then

		select SQL_NO_CACHE distinct value
		into 	l_value
		from 	variable
		where 	variable = trim(p_variable);

	end if;

	-- call log('DEBUG : END get_variable');

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns value associated with variable in customgnucash.variables
-- identical to get_variable except for 'deterministic' pragma and no SQL_NO_CACHE and no variable existence checking
-- used for repeating calls to the same variable where performance is an issue (such as create view account_map) and value wont change
drop function if exists get_constant;
//
create function get_constant
	(
		p_variable 	varchar(250)
	)
	returns text
	deterministic
begin
	declare l_value text default null;

	-- call log( concat('DEBUG : START get_constant(', ifnull(p_variable, 'null'), ')'));
	
	select distinct value
	into 	l_value
	from 	variable
	where 	variable = trim(p_variable);

	-- call log('DEBUG : END get_constant');

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns the date the variable was added (or amended)
drop function if exists get_variable_date;
//
create function get_variable_date
	(
		p_variable 	varchar(250)
	)
	returns timestamp
begin
	declare l_value timestamp default null;

	-- call log( concat('DEBUG : START get_variable_date(', ifnull(p_variable, 'null'), ')'));
	
	if 	exists_variable( p_variable) 
	--	and not is_locked('variable', 'WAIT')
	then

		select SQL_NO_CACHE distinct logdate
		into 	l_value
		from 	variable
		where 	variable = trim(p_variable);

	end if;

	-- call log('DEBUG : END get_variable_date');

	-- return convert_tz( l_value, get_constant('Default timezone'), 'UTC');
	return round_timestamp(l_value);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- adds a new variable/value pair to customgnucash.variables (does nothing if variable already there)
drop procedure if exists post_variable;
//
create procedure post_variable
	(
		p_variable 	varchar(250),
		p_value		text
	)
begin

	-- call log( concat('DEBUG : START post_variable(', ifnull(p_variable, 'null'), ')'));

	if	p_variable is not null
		and p_value is not null
		and not exists_variable( p_variable )
		-- and gnc_lock('variable') -- causes error when first adding vars
	then
		insert into 	variable (variable, value)
		values 		(trim(p_variable), trim(p_value));

		call gnc_unlock('variable');
	end if;

	-- call log('DEBUG : END post_variable');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- updates a variable/value pair to customgnucash.variables (does nothing if variable not already there, or new value is same as old value)
drop procedure if exists put_variable;
//
create procedure put_variable
	(
		p_variable 	varchar(250),
		p_value		text
	)
begin

	-- call log( concat('DEBUG : START put_variable(', ifnull(p_variable, 'null'), ',', ifnull(p_value, 'null'),')'));

	if 	p_variable is not null
		and p_value is not null
		and exists_variable(p_variable)
		and gnc_lock('variable')
	then
		update 	variable
		set 	value = trim(p_value)
		where 	variable = trim(p_variable)
		and 	value != trim(p_value);

		call gnc_unlock('variable');
	end if;

	-- call log('DEBUG : END put_variable');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- deletes a variable/value pair from customgnucash.variables (does nothing if variable not there)
drop procedure if exists delete_variable;
//
create procedure delete_variable
	(
		p_variable 	varchar(250)
	)
begin
	-- call log( concat('DEBUG : START delete_variable(', ifnull(p_variable, 'null'), ')'));

	if 	p_variable is not null
		and exists_variable(p_variable) 
		and gnc_lock('variable')
	then
		delete from 	variable
		where 		variable = trim(p_variable);

		call gnc_unlock('variable');
	end if;

	-- call log('DEBUG : END delete_variable');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [B.3] Extended commodity attribute routines

-- returns true if requested variable exists in customgnucash.commodity_attribute
drop function if exists exists_commodity_attribute;
//
create function exists_commodity_attribute
	(
		p_guid 		varchar(32), 	-- mandatory
		p_field		varchar(100), 	-- optional
		p_date		timestamp 	-- optional
	)
	returns boolean
begin
	declare l_exists	boolean default null;

	-- call log( concat('DEBUG : START exists_commodity_attribute(', ifnull(p_guid, 'null'), ',' , ifnull(p_field, 'null'), ',' , ifnull(p_date, 'null'), ')' ));	

	-- if not is_locked('commodity_attribute', 'WAIT') then

		select 	if(count(id) > 0, true, false)
		into 	l_exists
		from 	commodity_attribute
		where	upper(trim(p_guid))				= upper(trim(commodity_guid))
			and ifnull(upper(trim(p_field)), 'NULL') 	= ifnull(upper(trim(field)), 'NULL')
			and ifnull(p_date, current_timestamp) 		= ifnull(value_date, current_timestamp);
	-- end if;

	-- call log('DEBUG : END exists_commodity_attribute');

	return l_exists;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns value associated with variable in customgnucash.commodity_attribute
drop function if exists get_commodity_attribute;
//
create function get_commodity_attribute
	(
		p_guid 		varchar(32), 
		p_field		varchar(100), 
		p_date		timestamp 
	)
	returns text
begin
	declare l_value text default null;

	-- call log( concat('DEBUG : START get_commodity_attribute(', ifnull(p_guid, 'null'), ',' , ifnull(p_field, 'null'), ',' , ifnull(p_date, 'null'), ')' ));
	
	-- if 	exists_commodity_attribute(p_guid, p_field, p_date) 
	--	and not is_locked('commodity_attribute', 'WAIT')
	-- then

		select distinct value
		into 	l_value
		from 	commodity_attribute
		where	upper(trim(p_guid))				= upper(trim(commodity_guid))
			and ifnull(upper(trim(p_field)), 'NULL') 	= ifnull(upper(trim(field)), 'NULL')
			and ifnull(p_date, current_timestamp) 		>= ifnull(value_date, current_timestamp)
		order by value_date desc
		limit 1;
	-- end if;

	-- call log('DEBUG : END get_commodity_attribute');

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- adds a new variable/value pair to customgnucash.commodity_attribute 
-- does nothing if variable already there or p_guid is not a commodity
drop procedure if exists post_commodity_attribute;
//
create procedure post_commodity_attribute
	(
		p_guid 		varchar(32), 
		p_field		varchar(100), 
		p_date		timestamp,
		p_value		text
	)
procedure_block : begin

	-- call log( concat('DEBUG : START post_commodity_attribute(', ifnull(p_guid, 'null'), ',' , ifnull(p_field, 'null'), ',' , ifnull(p_date, 'null'), ',' , ifnull(p_value, 'null'), ')' ));
	
	-- dont bother trying to insert useless, incomplete, already inserted or very old values
	if 	length(trim(ifnull(p_value, '') )) = 0
		or p_value like '%missing%'
		or p_date is null
		or date_format(p_date, '%Y') = '0000'
		or p_date > current_timestamp
		or p_date < date_add(current_timestamp, interval - get_variable('Maximum quote age') year)
		-- or datediff(current_timestamp, p_date) > (365.25 * get_variable('Maximum quote age'))
		or not exists_commodity(p_guid)
		-- or exists_commodity_attribute(p_guid, p_field, p_date) 	-- specific to a date
		or get_commodity_attribute(p_guid, p_field, p_date) = p_value 	-- returns latest value

		-- log the fact this function is running so that it isnt accidentally called recursively later
		or not gnc_lock('post_commodity_attribute')

	then
		-- call log(concat('WARNING : Declined to load commodity attribute : p_guid=', ifnull(p_guid, 'null'), ', p_field=' , ifnull(p_field, 'null'), ', p_date=' , ifnull(p_date, 'null'), ', p_value=' , ifnull(p_value, 'null') ));
		leave procedure_block;
	end if;

	-- locking commodity_attribute here leads to deadlocks (see trigger propogate)
	insert into  commodity_attribute 
		(commodity_guid, field, value_date, value)
	values 		
		(trim(p_guid), trim(p_field), trim(p_date), trim(p_value) );

	call gnc_unlock('post_commodity_attribute');

	-- call log('DEBUG : END post_commodity_attribute');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- updates a variable/value pair to customgnucash.commodity_attribute (does nothing if variable not already there, or value hasnt changed)
drop procedure if exists put_commodity_attribute;
//
create procedure put_commodity_attribute
	(
		p_guid 		varchar(32), 
		p_field		varchar(100), 
		p_date		timestamp,
		p_value		text
	)
procedure_block : begin

	-- call log( concat('DEBUG : START put_commodity_attribute(', ifnull(p_guid, 'null'), ',' , ifnull(p_field, 'null'), ',' , ifnull(p_date, 'null'), ',' , ifnull(p_value, 'null'), ')' ));

	if	length(trim(ifnull(p_value, '') )) = 0
		or p_value like '%missing%'
		or p_date is null
		or not exists_commodity(p_guid)
		or not exists_commodity_attribute(p_guid, p_field, p_date)
		or ifnull(get_commodity_attribute(p_guid, p_field, p_date), 'NULL') = p_value
	then
		leave procedure_block;
	end if;

	update 		commodity_attribute
	set 		value = trim(p_value)
	where 		upper(trim(p_guid))			= upper(trim(commodity_guid))
		and 	ifnull(upper(trim(p_field)), 'NULL') 	= ifnull(upper(trim(field)), 'NULL')
		and 	ifnull(p_date, 'NULL') 			= ifnull(value_date, 'NULL');

	-- call log('DEBUG : END put_commodity_attribute');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- deletes a variable/value pair from customgnucash.commodity_attribute (does nothing if variable not there)
-- if p_field or p_date are null, will delete *all* matching records, ignoring p_field or p_date (dangerous!)
drop procedure if exists delete_commodity_attribute;
//
create procedure delete_commodity_attribute
	(
		p_guid 		varchar(32), 
		p_field		varchar(100), 
		p_date		timestamp 
	)
procedure_block : begin

	-- call log( concat('DEBUG : START delete_commodity_attribute(', ifnull(p_guid, 'null'), ',' , ifnull(p_field, 'null'), ',' , ifnull(p_date, 'null'), ')' ));

	if  	exists_commodity_attribute(p_guid, p_field, p_date) 
		and gnc_lock('commodity_attribute')
	then

		delete from 	commodity_attribute
		where 		upper(trim(p_guid))			= upper(trim(commodity_guid))
			and 	ifnull(upper(trim(p_field)), 'NULL') 	= ifnull(upper(trim(field)), 'NULL')
			and 	ifnull(p_date, 'NULL') 			= ifnull(value_date, 'NULL');

		call gnc_unlock('commodity_attribute');
	end if;

	-- call log('DEBUG : END delete_commodity_attribute');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- deletes *all* attributes derived from a price, for a given commodity, from a given date
-- for use when updating or inserting prices out of order
drop procedure if exists delete_derived_commodity_attributes;
//
create procedure delete_derived_commodity_attributes
	(
		p_guid 		varchar(32), 
		p_date		timestamp 
	)
procedure_block : begin

	-- call log( concat('DEBUG : START delete_derived_commodity_attributes(', ifnull(p_guid, 'null'), ',' , ifnull(p_date, 'null'), ')' ));

	if gnc_lock('commodity_attribute') then

		delete from	commodity_attribute
		where		upper(trim(commodity_guid)) = upper(trim(p_guid))
			and	round_timestamp(value_date) >= round_timestamp(p_date)
			and	(field like 'sma%' or field like 'ema%' or field like 'so%' or field like 'ppo%' or field like 'macd%');

		call gnc_unlock('commodity_attribute');
	end if;

	-- call log('DEBUG : END delete_derived_commodity_attributes');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [B.4] Array management routines

-- MySQL (Ver 15.1 Distrib 5.5.39-MariaDB) doesn't support arrays
-- this workaround uses CSV strings instead
-- workarounds dont work with '' or ' ' as a separator

-- gets a +ve or -ve numbered element from a CSV list 
-- ie get_element('A,B,C,D', -2, ',') = 'C'
-- standard MySQL function make_set does something similar
drop function if exists get_element;
//
create function get_element
	(
		p_array		text, -- varchar(60000),
		p_index		int,
		p_separator	char(1)
	)
	returns text -- varchar(1000),
	no sql
begin
	declare l_len 		int;
	declare l_count 	int;

	set p_index = ifnull(p_index,0);
	set p_separator = ifnull(p_separator, ',');
	set p_array = trim( p_separator from p_array);
	set l_count = get_element_count( p_array, p_separator);

	-- short circuits
	-- if p_index=0, or p_index=1 and l_count=1, just return array unchanged
	if (p_index = 1 and l_count = 1) or p_index = 0 then
		return p_array;
	end if;

	-- if element is out of range
	if abs( p_index ) > l_count then
		return null;
	end if;

	-- check if we are working from the beginning or end of the string
	if p_index > 0 then
		set l_len = -1;
	else
		set l_len = 1;
	end if;

	return trim(substring_index( substring_index(  p_array , p_separator , p_index ), p_separator, l_len));
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns the number if elements in an array (ie, a CSV string)
drop function if exists get_element_count;
//
create function get_element_count
	(
		p_array		text, -- varchar(60000),
		p_separator	char(1)
	)
	returns int
	no sql
begin
	set p_separator = ifnull(p_separator, ',');
	set p_array = trim( p_separator from p_array);

	return length( p_array ) - length( replace( p_array, p_separator, '' )) + 1;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- adds an element to a CSV string
-- uses group_concat rather than concat because former has hardcoded limit but latter can be set via group_concat_max_len (needs to be > default of 1024; recommended 60000)
drop procedure if exists put_element;
//
create procedure put_element
	(
		inout	p_array		text, -- varchar(60000),
		in	p_element	text, -- varchar(60000),
		in	p_separator	char(1)
	)
begin
	set p_separator = ifnull(p_separator, ',');
	if trim(p_element) is not null then

		select 	trim( p_separator from group_concat(strings.str) )
		into 	p_array
		from	
		(	select trim(ifnull(p_array, '' )) as str
			union
			select trim(p_element)
		) strings;
			
		-- set p_array = trim( p_separator from concat( ifnull(p_array, '' ), p_separator, p_element) );
	end if;
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- sorts an array (actually a CSV string)
-- could be done algorithmically via quick sort etc, but decided to hope that native MySQL sorting is better optimised
drop function if exists sort_array;
//
create function sort_array
	(
		p_array		text, -- varchar(60000),
		p_flag		char(1), -- 'u' for unique sort; default null to include all values, dupes and all
		p_separator	char(1)
	)
	returns text -- varchar(60000)
begin
	declare l_sorted_array 		text; -- varchar(60000);
	declare l_count 		int;
	declare l_element 		text; -- varchar(1000);
	declare l_tally_done 		boolean default false;
	declare l_tally_done_temp	boolean default false;

	set l_count = 1;
	set p_separator = ifnull(p_separator, ',');
	set p_flag = ifnull(p_flag, 'n'); -- default nonunique sort

	drop temporary table if exists tally;
	create temporary table tally (
		element			varchar(1000)
	);
	
	while l_count <= get_element_count(p_array, p_separator) do

		insert into tally
		values
		( get_element(p_array, l_count, p_separator) );

		set l_count = l_count + 1;

	end while;

	tally_block : begin -- tally block

		declare lc_tally cursor for
			select 
				element
			from tally
			order by element;
		
		declare lc_tally_u cursor for
			select distinct
				element
			from tally
			order by element;
									
		declare continue handler for not found set l_tally_done =  true;
										
		-- if p_flag = 'u' then 
		-- this p_flag comparison doesnt work here (but it does below!); must be some MySQL weirdness about cursors
			open lc_tally_u;
		-- else
			open lc_tally;
		-- end if;

		set l_tally_done = false;

		-- process in order, adding sorted elements to a new array
		tally_loop : loop

			if p_flag = 'u' then
				fetch lc_tally_u into l_element;
			else
				fetch lc_tally into l_element;
			end if;		
											
			-- stop processing if there's no data 
			if l_tally_done then 
				leave tally_loop;
			else
				set l_tally_done_temp = l_tally_done;
			end if;
 
			call put_element(l_sorted_array, l_element, p_separator);

		end loop; -- tally_loop

		close lc_tally;

		set l_tally_done = l_tally_done_temp;

	end; -- tally block	
	
	return l_sorted_array;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [B.5] Locking routines
-- these actually manage mutex arbitrary strings which proxy for tables, functions or anything else

-- [R] returns true if any named lock is in use
-- returns true if ANY lock is in force, false if ALL locks are NOT in force
-- can (optionally) use a WAIT parameter to cause function to iterate until all locks are freed
drop function if exists is_locked;
//
create function is_locked
	(
		p_locks 	varchar(1000), 	-- CSV list of locks to check
		p_mode		varchar(10)	-- 'WAIT' or anything else (which is read as 'NOWAIT')
	)
	returns boolean
	no sql
begin
	declare l_lock 		boolean;
	declare l_count		int;
	declare l_start		timestamp default sysdate();

	-- call log( concat('DEBUG : START is_locked(', ifnull(p_locks, 'null'), ',', ifnull(p_mode, 'null'), ')' ));

	repeat
		set l_count = 1;
		set l_lock = false;
		while_loop : while l_count <= get_element_count(p_locks, ',') 
		do
			if is_used_lock(get_element(p_locks, l_count, ',')) is not null
			then
				set l_lock = true;
				leave while_loop;
			end if;
			set l_count = l_count + 1;
		end while;

		-- if WAIT requested, and locked ...
		if 	p_mode = 'WAIT' 
			and l_lock
		then
			-- wait a random number of seconds (between 0 and 5), to avoid resonance with other lock waits
			do sleep( rand() * 5 );
		end if;

	until 	p_mode != 'WAIT'
		or not l_lock
		or
		(	p_mode = 'WAIT'
			and timestampdiff(SECOND, l_start, sysdate()) >= ifnull(get_variable('Lock wait'), 60)
		)
	end repeat;

	-- call log('DEBUG : END is_locked');

	return l_lock;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] unlocks Gnucash and Customgnucash databases
-- means that GnuCash application wont complain about this database lock on startup
drop procedure if exists gnc_unlock;
//
create procedure gnc_unlock
	(
		p_locks		varchar(1000) -- CSV string of lock names
	)
procedure_block:begin
	declare l_count					int default 1;
	declare l_gnucash_db_unlock_required 		boolean default false;
	declare	l_error					varchar(1000);

	-- call log( concat('DEBUG : START gnc_unlock(', ifnull(p_locks, 'null'), ')' ));
	
	-- initialise (remove dupes from list, lock gnucash db by default)
	set p_locks = ifnull( sort_array(p_locks, 'u', ','), get_constant('Gnucash schema') );

	-- attept to grab each lock in turn; fail if ANY lock cannot be obtained
	while_loop : while l_count <= get_element_count(p_locks, ',') and l_error is null
	do
		-- revoke named lock
		if release_lock( get_element(p_locks, l_count, ',')) = 1
		then

			-- work out if the lock refers to the gnucash db (or its tables)
			if not l_gnucash_db_unlock_required then

				if get_element(p_locks, l_count, ',') = get_constant('Gnucash schema') 
				then
					set l_gnucash_db_unlock_required = true;
				else
					select 	if(count(*)> 0, true, false) 
					into 	l_gnucash_db_unlock_required
					from 	information_schema.tables
					where	table_type = 'BASE TABLE'
					and	upper(table_name) = upper(get_element(p_locks, l_count, ','))
					and 	upper(table_schema) = upper(get_constant('Gnucash schema'));
				end if;

				-- if the above calc shows that a gnucash db lock is required ...
				if l_gnucash_db_unlock_required then

					-- delete *ONE* lock only (other customgnucash processes may also have locked gnucash)
					delete
					from 	gnclock
					where 	hostname = schema()
					and 	pid = connection_id()
					limit 	1;

				end if; -- if l_gnucash_db_lock_required 

			end if; -- if not l_gnucash_db_lock_required
		else
			set l_error = concat('WARNING : Unable to release lock "', get_element(p_locks, l_count, ','), '"');
		end if;

		set l_count = l_count + 1;

	end while;

	-- call log('DEBUG : END gnc_unlock');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [RW] Locks Gnucash database and/or specified tables for writing (actually a mutex lock using arbitrary strings that do not have to map to tablenames)
-- [1] Gnucash database lock is designed to cause the GnuCash application to warn about being unable to obtain database locks (which can be overidden by the GUI user with unpredictable results) AND to abort write CustomGnuCash operations whilst the GnuCash GUI is open
-- [2] Table locks are a customised implementation of MySQL "get_lock" that works between sessions (ie between a mysql-scheduled routine that updates prices, and the cron-scheduled routine that updates prices).
-- [3] Although designed for table locking (by proxy), can alos be used to lock procedures, functions, events etc
-- uses variable get_variable('lock wait') to retry each lock over 'lock wait' seconds before giving up
-- returns true on success (of all locks), false on failure (of any lock)

drop function if exists gnc_lock;
//
create function gnc_lock
	(
		p_locks		varchar(1000) -- CSV string of lock names
	)
	returns boolean
begin
	declare l_obtained_locks			varchar(1000);
	declare l_gnucash_db_lock_required 		boolean default false;
	declare l_customgnucash_db_lock_required 	boolean default false;
	declare l_count					int default 1;
	declare l_lock_count				int default 0;
	declare	l_error					varchar(1000);

	-- call log( concat('DEBUG : START gnc_lock(', ifnull(p_locks, 'null'), ')' ));

	-- initialise (remove dupes from list, lock gnucash db by default)
	set p_locks = ifnull( sort_array(p_locks, 'u', ','), get_constant('Gnucash schema') );

	-- attept to grab each lock in turn; fail if ANY lock cannot be obtained
	while_loop : while l_count <= get_element_count(p_locks, ',') and l_error is null
	do
		-- get named lock
		if get_lock( get_element(p_locks, l_count, ','), ifnull(get_variable('Lock wait'),60) ) = 1
		then
			-- maintain a list of obtained locks
			call put_element(l_obtained_locks, get_element(p_locks, l_count, ','), ',');
		else
			set l_error = concat('ERROR : Unable to obtain lock "', get_element(p_locks, l_count, ','), '"');
		end if;

		-- work out if the lock refers to the gnucash db (or its tables)
		if not l_gnucash_db_lock_required then

			if get_element(p_locks, l_count, ',') = get_constant('Gnucash schema') 
			then
				set l_gnucash_db_lock_required = true;
			else
				select 	if(count(*)> 0, true, false) 
				into 	l_gnucash_db_lock_required
				from 	information_schema.tables
				where	table_type = 'BASE TABLE'
				and	upper(table_name) = upper(get_element(p_locks, l_count, ','))
				and 	upper(table_schema) = upper(get_constant('Gnucash schema'));
			end if;

			-- if the above calc shows that a gnucash db lock is required ...
			if l_gnucash_db_lock_required then

				-- attempt to get gnucash lock if gnucash status allows
				if get_variable('Gnucash status') != 'RW' then

					set l_error = concat('WARNING : Unable to lock gnucash schema "', 
							ifnull(get_constant('Gnucash schema'), 'unknown'),
							'" because it is marked as unwriteable "', get_variable('Gnucash status') ,'"'
							);
				else
					-- the gnucash lock is to avoid clashing with the GnuCash GUI, so we can have as many as we like as long as the GUI isnt already using it
					select 	count(*)
					into 	l_lock_count
					from 	gnclock
					where 	hostname != schema();

					if l_lock_count = 0 then

						insert into gnclock
						values(
							schema(),
							connection_id()
						);

						select 	count(*)
						into 	l_lock_count
						from 	gnclock
						where 	hostname = schema()
						and 	pid = connection_id();

						if l_lock_count > 0 then
							call put_element(l_obtained_locks, get_constant('Gnucash schema'), ',');
						else
							set l_error = concat('ERROR : Unable to lock gnucash schema "', 
									ifnull(get_constant('Gnucash schema'), 'unknown'),
									'"'
								);
						end if;
					else
						set l_error = concat('ERROR : Unable to lock gnucash schema "', 
								ifnull(get_constant('Gnucash schema'), 'unknown'),
								'" because it is already locked by the Gnucash GUI.'
							);
					end if; -- if l_lock_count = 0

				end if; -- if get_variable('Gnucash status') != 'RW'

			end if; -- if l_gnucash_db_lock_required 

		end if; -- if not l_gnucash_db_lock_required

		-- work out if the lock refers to the customgnucash db (or its tables)
		if not l_customgnucash_db_lock_required then

			if get_element(p_locks, l_count, ',') = schema() 
			then
				set l_customgnucash_db_lock_required = true;
			else
				select 	if(count(*)> 1, true, false) 
				into 	l_customgnucash_db_lock_required
				from 	information_schema.tables
				where	table_type = 'BASE TABLE'
				and	table_name = get_element(p_locks, l_count, ',')
				and 	table_schema = schema();
			end if;

			-- if the above calc shows that a customgnucash db lock is required ...
			if 	l_customgnucash_db_lock_required 
				and get_variable('Customgnucash status') != 'OK' 
			then
				set l_error = concat('ERROR : Unable to lock customgnucash schema "', 
						schema(),
						'" because its status is "', get_variable('Customgnucash status') ,'"'
						);
			end if;
		end if;

		set l_count = l_count + 1;
	end while;

	-- if theres been an error ...
	if l_error is not null then

		-- log the error
		call log( l_error);

		-- undo locks created so far
		call gnc_unlock( sort_array(l_obtained_locks, 'u', ','));

		-- return false signal
		return false;
	end if;

	-- call log('DEBUG : END gnc_lock');

	-- if youve got this far, return true signal
	return true;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [B.6] Miscellaneous standalone routines

-- rounds a timestamp to the appropriate day (so '2010-06-15 23:00:00'-> '2010-06-16 00:00:00' & '2010-01-15 00:00:00'-> '2010-06-15 00:00:00')
-- catering for local time and daylight savings (to deal with GnuCash's tendency to truncate dates to midnight, which is 23:00 UTC the previous day in DST)
-- this is a bit iffy; according to the MySQL & MariaDB doc, timestamp fields are automatically converted to local time on retrieval, 
-- but inspection of transaction.post_date suggests this is not the case
drop function if exists round_timestamp;
//
create function round_timestamp
	(
		p_timestamp	timestamp
	)
	returns timestamp
	no sql
	deterministic
begin
	return from_days(to_days( convert_tz(p_timestamp, 'UTC', get_variable('Default timezone')) ));
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns true if input looks like a GUID (a 32 char length string which is a hex number)
drop function if exists is_guid;
//
create function is_guid
	(
		p_in	varchar(35)
	)
	returns boolean
	no sql
	deterministic
begin
	if 	length(p_in) = 32
		and unhex(p_in) is not null
	then
		return true;
	else
		return false;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns true if input looks like a numeral (-ve, 0, integer or floating point)
-- regexp needs tidying up (is an IP address really a number?)
drop function if exists is_number;
//
create function is_number
	(
		p_in	varchar(1000)
	)
	returns boolean
	deterministic
begin
	declare l_value boolean default false;

	-- trip leading or trailing spaces
	set p_in = trim(p_in);

	-- short circuit if input is blank
	if p_in is null 
	or length(p_in) = 0
	then
		return l_value;
	end if;

	select 	p_in regexp '^[[:digit:]\.]+$'
	into 	l_value;

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns new random guid for use when inserting rows into GnuCash tables
-- I don't know what algorithm GnuCash actually uses to generate these
drop function if exists new_guid;
//
create function new_guid ()
	returns varchar(32)
	no sql
begin
	-- return md5(rand());
	return replace(uuid(), '-', '');
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- returns timestamp of tax year
-- p_index=0 this tax year (ie next April), p_index=-1 last tax year, p_index=-2 start of the last completed tax year etc
drop function if exists get_tax_year_end;
//
create function get_tax_year_end
	(
		p_index	int
	)	
	returns timestamp
begin
	if exists_variable('Tax year end') then
		
		-- if we've already passed tax year end for this calendar year ...
		if current_timestamp > str_to_date( concat( get_variable('Tax year end'), extract(year from current_timestamp)), '%d %M %Y') then
			-- then tax year end is next calendar year
			return str_to_date( concat( get_variable('Tax year end'), extract(year from (current_timestamp + interval ( ifnull(p_index,0) + 1) year )), '00:00:00'), '%d %M %Y %H:%i:%s');
		else
			return str_to_date( concat( get_variable('Tax year end'), extract(year from (current_timestamp + interval ifnull(p_index,0) year )), '00:00:00'), '%d %M %Y %H:%i:%s');
		end if;

	else
		return null;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- some functions store useful series of data in the "variable" table; this function helps extract it
-- variable.value is assumed to be the y-axis value
-- example : in table, where variable="get_commodity_ema(abcdef,20,2010-10-01)" then value="2.2" (and you can get others for 2010-10-02, 2010-10-03 etc)
-- so, get_series('get_commodity_ema', '1=abcdef,2=20' ,3) returns a table with row x=2010-10-01 y=2.2 (and you can get rows for other dates etc)
-- returns a table-like datastructure that is only useful for human reading; it cant be used by other procedures or functions
drop procedure if exists get_series;
//
create procedure get_series
	(
		p_series_name			varchar(64), 	-- the name of the series (usually a function name like 'get_commodity_ema')
		p_criteria			varchar(700), 	-- field specification criteria
		p_x_axis			int		-- the number of the field which will act as x-axis (usually the date field)
	)
procedure_block : begin
	declare l_fieldspec			varchar(700);
	declare l_criterion 			varchar(100);
	declare l_criterion_position 		int;
	declare l_criterion_previous_position 	int;
	declare l_criterion_string 		varchar(100);
	declare l_count 			int;
	declare l_separator			char(1);

	set l_count=1;
	set l_criterion_previous_position=0;

	-- put fieldspec into standard order
	set l_fieldspec = concat('^' , p_series_name , '(');
	set p_criteria = sort_array(p_criteria, 'u', null);

	-- loop through each element in user defined fieldspec
	while l_count <= get_element_count(p_criteria, ',') do

		if l_count = 1 then
			set l_separator = '';
		else
			set l_separator = ',';
		end if;
	
		set l_criterion = get_element(p_criteria, l_count, ',');
		set l_criterion_position = get_element(l_criterion, 1, '=');
		set l_criterion_string = get_element(l_criterion, 2, '=');
	
		-- if fields are skipped, add a caveat in l_fieldspec
		if l_criterion_position != l_criterion_previous_position + 1 then
			set l_fieldspec  =  concat(l_fieldspec , 
							repeat( 
								concat(l_separator , '.+'), 
								l_criterion_position - l_criterion_previous_position - 1 
							) 
						);
		end if;

		set l_fieldspec = concat(l_fieldspec , l_separator , l_criterion_string);
		set l_criterion_previous_position = l_criterion_position;
		set l_count = l_count + 1;

	end while;

	-- correct fieldspec for regexp use
	set l_fieldspec = replace(l_fieldspec, '(', '\\(');
	set l_fieldspec = replace(l_fieldspec, ')', '\\)');

	-- extract data
	select
		get_element(
			replace(
				replace(
					variable.variable,
					concat(p_series_name , '('),
					''
					),
				')',
				''
				),
			p_x_axis, 
			','
			) as x,
		variable.value as y
	from
		variable
	where
		variable.variable regexp (l_fieldspec)
	order by 1;

end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- deletes series from variables table
-- example : SQL> delete_series('get_account_costs', '1=3836f80609ee4678e1058e33592031d1'); 
-- deletes *all* previously calculated account costs for account 3836f80609ee4678e1058e33592031d1
drop procedure if exists delete_series;
//
create procedure delete_series
	(
		p_series_name			varchar(64), -- the name of the series (usually a function name like 'get_commodity_ema')
		p_criteria			varchar(700) -- field specification criteria (if null, then all of p_series_name will be deleted)
	)
procedure_block : begin
	declare l_fieldspec			varchar(700);
	declare l_criterion 			varchar(100);
	declare l_criterion_position 		int;
	declare l_criterion_previous_position 	int;
	declare l_criterion_string 		varchar(100);
	declare l_count 			int;
	declare l_separator			char(1);

	-- call log('DEBUG : START delete_series');

	set l_count=1;
	set l_criterion_previous_position=0;

	-- put fieldspec into standard order
	set l_fieldspec = concat('^' , p_series_name , '(');

	if p_criteria is not null then

		set p_criteria = sort_array(p_criteria, 'u', null);

		-- loop through each element in user defined fieldspec
		while l_count <= get_element_count(p_criteria, ',') do

			if l_count = 1 then
				set l_separator = '';
			else
				set l_separator = ',';
			end if;
	
			set l_criterion = get_element(p_criteria, l_count, ',');
			set l_criterion_position = get_element(l_criterion, 1, '=');
			set l_criterion_string = get_element(l_criterion, 2, '=');
	
			-- if fields are skipped, add a caveat in l_fieldspec
			if l_criterion_position != l_criterion_previous_position + 1 then
				set l_fieldspec  =  concat(	l_fieldspec , 
								repeat( 
									concat(l_separator , '.+'), 
									l_criterion_position - l_criterion_previous_position - 1 
								) 
							);
			end if;

			set l_fieldspec = concat(l_fieldspec , l_separator , l_criterion_string);
			set l_criterion_previous_position = l_criterion_position;
			set l_count = l_count + 1;

		end while;

	end if; -- if p_criteria is not null

	-- correct fieldspec for regexp use
	set l_fieldspec = replace(l_fieldspec, '(', '\\(');
	set l_fieldspec = replace(l_fieldspec, ')', '\\)');

	-- delete specified series
	delete
	from
		variable
	where
		variable.variable regexp (l_fieldspec);

	-- call log('DEBUG : END delete_series');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] Gnucash has this ragbag-of-stuff table called slots for which there is no documentation
-- always returns varchar (even if actually a number) because actual datatype returned is undefined
drop function if exists get_slot;
//
create function get_slot
	(
		p_guid  varchar(32),
		p_name	varchar(4096)
	)
	returns varchar(4096)
begin
	declare l_slot_type		int(11);
	declare l_int64_val		bigint(20);
	declare	l_string_val		varchar(4096);
	declare	l_double_val		double;
	declare	l_timespec_val		timestamp;
	declare	l_guid_val		varchar(32);
	declare	l_numeric_val		decimal(20,6);
	declare	l_gdate_val		date;

	-- call log( concat('DEBUG : START get_slot(', ifnull(p_guid, 'null'), ',', ifnull(p_name, 'null'), ')' ));

	-- sanity check inputs
	if 	p_guid is null
		or p_name is null
	then
		return null;
	end if;
	
	select
		slot_type,
		int64_val,
		string_val,
		double_val,
		timespec_val,
		guid_val,
		numeric_val_num / ifnull(numeric_val_denom,1),
		gdate_val
	into	
		l_slot_type,
		l_int64_val,
		l_string_val,
		l_double_val,
		l_timespec_val,
		l_guid_val,
		l_numeric_val,
		l_gdate_val
	from
		slots
	where
		obj_guid = p_guid
		and name = p_name;

	-- it would be ideal to know what slot_types mean
	case
		-- known slot_types
		when l_slot_type 	in (5,9)	then return l_guid_val;
		when l_slot_type 	= 3		then return convert(l_numeric_val, char);
		when l_slot_type 	= 4		then return l_string_val; 
		when l_slot_type 	= 10		then return convert(l_gdate_val, char);

		-- unknown slot_type : these fields are null when not in use
		when l_timespec_val 	is not null 	then return convert(l_timespec_val, char);

		-- unknown slot_type : these fields are 0 when not in use (or if they are really zero!)
		else
			if l_int64_val 		!= 0 	then 
				return convert(l_int64_val, char);
			elseif l_double_val 	!= 0 	then 
				return convert(l_double_val, char);
			else
				-- value cant be any of those defined by slot_type, or null-when-unused, so it must be int64_val or double_val, hence zero
				return '0';
			end if;
	end case;

	-- call log('DEBUG : END get_slot');

	return l_out;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [C] REPORTING ROUTINES

-- returns pluralised form of p_text if p_number is not 1, ready for use in reports
-- needs amendment to deal with the many exceptions in English
drop function if exists pluralise;
//
create function pluralise
	(
		p_number	decimal(20,6),
		p_text		varchar(50)
	)
	returns varchar(50)
	deterministic
	no sql
begin
	declare l_out varchar(50);

	-- depluralise first to start with known 
	set p_text = trim(trailing 's' from p_text);

	if p_number != 1 then
		set l_out = concat(trim( trailing '.' from trim( trailing '0' from convert(p_number, char))), ' ', p_text, 's');
	else
		set l_out = concat('one ', p_text);
	end if;

	return l_out;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- converts a decimal to 2 dp and a character string, or '&nbsp;' (an HTML non-breaking space) if null or zero
-- used to 'prettify' HTML reports and ensure no MySQL collation errors or concat-returns-null-if-anything-concated-is-already-null problems
drop function if exists prettify;
//
create function prettify
	(
		p_value		decimal(20,6)
	)
	returns varchar(1000)
	deterministic
	no sql
begin
	declare l_value varchar(1000);
	
	case
		when p_value = 0 then
			set l_value = '&nbsp;';		
		when p_value is null then 
			set l_value = '<table class=null_field><tr><td>&nbsp;</td></tr></table>';
		else 
			set l_value = convert( round(	p_value, 2), char);		
	end case;

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- converts a number into an html 'bar'
-- ie "select html_bar(10, 'red')" outputs html to give a table of 1 row with 10 red cells in it
-- yes, I know its cheap and nasty, but it works simply and predictably in html emails
drop function if exists html_bar;
//
create function html_bar
	(
		p_value 	decimal(20,6),
		p_colour	varchar(50)
	)
	returns varchar(5000)
	deterministic
	no sql
begin
	return concat(
			'<table class=html_bar bgcolor=', ifnull(p_colour,'black'), '><tr>',
			repeat('<td>&nbsp;</td>', round(p_value,0)),
			'</tr></table>'
		);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- writes a new line to a given variable (for creating long text reports)
-- p_style = plain : no formatting; 
-- table-start : top of html table; 
-- table-end : bottom of html table; 
-- table-middle : middle of html table; 
-- title : "TITLE:" line at top of report ready for emailing
drop procedure if exists write_report;
//
create procedure write_report
	(
		inout	p_report	text, 	-- for convenience, if this is a string of values delimited by '|' (pipe symbol), it is assumed to be a row in a data table
		in	p_line		varchar(2048),
		in 	p_style		varchar(20)		
	)
	no sql
procedure_block : begin

	-- call log( concat('DEBUG : START write_report(', ifnull(p_line, 'null'), ',', ifnull(p_style, 'null'), ')' ));

	-- usually, dont bother continuing if p_line is null
	-- but can do so if p_style is table-end (where no new data row is required)
	if 	p_line is not null 
		or p_style = 'table-end'
	then

		-- default as plaintext
		set p_style = lower(ifnull(p_style, 'plain'));

		case p_style

			when 'table-start' then

				-- call log('table-start');
				set p_report = concat( 	'<table class=main style="width:100%"> <tr> <th> ',
							replace(p_line, '|', '</th> <th> '),
							'</th> </tr>',
							ifnull(p_report, '')
						);

			when 'table-middle' then
		
				-- call log('table-middle');
				set p_report = concat( 	ifnull(p_report, ''),
							'<tr> <td>',
							replace(p_line, '|', '</td> <td> '),
							'</td> </tr>'
						);
										
			when 'table-end' then

				-- call log('table-end');
				set p_report = concat(	ifnull(p_report, ''),
							'</table>'
						);
			when 'title' then
				
				set p_report = concat(	'\nTITLE:',
							trim(p_line),
							'\n',
							ifnull(p_report, '')
						);

			else

				-- call log('plain');
				set p_report = concat(	ifnull(p_report, ''),
							if(p_report is not null, '</br>', ''),
							p_line
						);

		end case;

	end if; -- if p_line is not null

	-- call log('DEBUG : END write_report');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- extracts reports from variables table 
-- designed to be called by a commandline or scripted OS (eg linux) function 
-- returns text of p_num (usually 1) reports, then deletes said report from variables table so its not extracted again
-- consequently, it needs to be called from the OS scheduler regularly (at least once an hour) in order to work through any queue
-- if p_num >1 then >1 reports will be emitted in one lump of text
drop procedure if exists get_report;
//
create procedure get_report 
	( 
		p_num 	int
	)
procedure_block : begin
	declare l_variable 		varchar(250);
	declare l_value 		text; 
	declare l_report 		text;
	declare l_html_header 		varchar(500);
	declare l_html_footer 		varchar(50);
	declare l_report_done_temp 	boolean default false;
	declare l_report_done 		boolean default false;

	declare lc_report cursor for
		select distinct 
			variable, 
			value 
		from 
			variable 
		where 
			variable like 'report\_%' 
		order by 
			logdate asc 
		limit 	p_num;
	declare continue handler for not found set l_report_done =  true;

	-- call log( concat('DEBUG : START get_report(', ifnull(p_num, 'null'), ')' ));

	-- try to play nicely with other procedures
	do is_locked('variable', 'WAIT');

	set l_html_header = concat(	'<html><head><style>',
					get_variable('Report CSS'),
					'</style></head><body>'
				);

	set l_html_footer = '</body></html>';

	-- only collect p_num reports, or as many as there are, whichever is least
	select 	least(count(*), ifnull(p_num, 1)) 
	into 	p_num 
	from 	variable 
	where 	variable.variable like 'report\_%';

	open lc_report;
	set l_report_done = false;

	report_loop : loop

		fetch lc_report into l_variable, l_value;

		if l_report_done then 
			leave report_loop;
		else
			set l_report_done_temp = l_report_done;
		end if;

		if l_value is not null then
			set l_report = concat( 
						ifnull(l_report,''), 
						if(l_report is not null,'<br><hr><br>', ''), 
						ifnull(l_value,'') 
					);
		end if;

		-- delete report from variables table
		call delete_variable(l_variable);

		set l_report_done = l_report_done_temp;
													
	end loop; -- report_loop

	-- return report if there is one
	if l_report is not null then
		select concat(l_html_header, l_report, l_html_footer) as report;
	else
		-- needs to return '' not NULL so calling linux script can see there is nothing in the report
		select '' as report;
	end if;

	-- call log('DEBUG : END get_report');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [D] COMMODITY ROUTINES

-- [R] returns true if specified mnemonic ('GBP', 'IUKD.L') or commodity guid exists in the gnucash database
drop function if exists exists_commodity;
//
create function exists_commodity
	(
		p_in 	varchar(32)
	)
	returns boolean
begin
	declare l_count 	int default 0;

	-- check sane values
	if p_in is null
	then
		return null;
	else
		-- standardise input (uppercase, trimmed of spaces and account separators
		set p_in = trim( upper(p_in) );
	end if;

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	if is_guid(p_in) then

		-- p_in is probably a guid
		select 	count(guid)
		into 	l_count
		from 	commodities
		where 	upper( trim( guid )) = p_in;

	else
		-- p_in is probably a name
		select 	count(guid)
		into 	l_count
		from 	commodities 
		where 	upper( trim( mnemonic )) = p_in;

	end if;

	if l_count = 0 then	
		return false;
	else 
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] gets namespace ('EUREX', 'CURRENCY') for specified commodity
drop function if exists get_commodity_namespace;
//
create function get_commodity_namespace
	(
		p_guid 		varchar(32)
	)
	returns varchar(2048)
begin
	declare l_namespace 	varchar(2048);

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	select distinct namespace 
	into 	l_namespace 
	from 	commodities
	where	guid = p_guid
	limit 	1;

	return trim(l_namespace);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if specified commodity namespace is 'CURRENCY'
-- note that commodity indices such as XAU (gold) is also considered a currency (by GnuCash, not by me!)
drop function if exists is_currency;
//
create function is_currency
	(
		p_guid 		varchar(32)
	)
	returns boolean
begin
	if upper(get_commodity_namespace(p_guid)) = 'CURRENCY' then return true;
	else return false;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns guid for given commodity mnemonic
drop function if exists get_commodity_guid;
//
create function get_commodity_guid
	(
		p_mnemonic 	varchar(2048)
	)
	returns varchar(32)
begin
	declare l_guid 		varchar(32);

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	select distinct guid 
	into 	l_guid 
	from 	commodities
	where 	upper(mnemonic) = upper(p_mnemonic) 
	limit 	1;

	return trim(l_guid);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns guid for default currency (set up by "call post_variable ('Default currency', 'GBP');"
-- just a convenience function; merely calls get_commodity_guid with correct parameters
drop function if exists get_default_currency_guid;
//
create function get_default_currency_guid()
	returns varchar(32)
	deterministic
begin
	return get_commodity_guid( get_constant('Default currency'));
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns mnemonic ('GBP', 'IUKD.L) for given commodity guid
drop function if exists get_commodity_mnemonic;
//
create function get_commodity_mnemonic
	(
		p_guid 		varchar(32)
	)
	returns varchar(2048)
begin
	declare l_mnemonic 	varchar(2048);

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	select distinct	mnemonic 
	into 	l_mnemonic 
	from 	commodities 
	where 	guid = p_guid
	limit 	1;

	return trim(l_mnemonic);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns name for given commodity guid
drop function if exists get_commodity_name;
//
create function get_commodity_name
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
begin
	declare l_name varchar(2048);

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	select distinct	fullname 
	into 	l_name 
	from 	commodities 
	where 	guid = p_guid
	limit 	1;

	return trim(l_name);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the currency in which a commodity is quoted
drop function if exists get_commodity_currency;
//
create function get_commodity_currency
	(
		p_guid varchar(32)
	)
	returns varchar(32)
begin
	declare l_guid varchar(32);

	-- short circuit if commodity provided is the default currency
	if p_guid = get_default_currency_guid() then
		return p_guid;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	select distinct	currency_guid 
	into 	l_guid
	from 	prices 
	where 	commodity_guid = p_guid
	limit 	1;

	return trim(l_guid);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if a quote (aka price or value) exists for a commodity on a given date
drop function if exists exists_price;
//
create function exists_price
	(
		p_guid		varchar(32),
		p_date		timestamp
	)
	returns 		boolean
begin
	declare l_count int;

	-- set default date
	set p_date = ifnull(p_date, current_timestamp);

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	select 	count(*)
	into 	l_count
	from	prices
	where	commodity_guid = p_guid
	and 	round_timestamp(date) = round_timestamp(p_date);

	if l_count > 0 then
		return true;
	else
		return false;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the price of a commodity (or currency) on the given date ("now" is default)
-- includes quoted prices and prices derived from actual transactions
-- the unit in which the value is returned is the commodity currency (get_commodity_currency(<commodity_guid>) )
drop function if exists get_commodity_price;
//
create function get_commodity_price
	(
		p_guid		varchar(32),
		p_date		timestamp
	)
	returns 		decimal (15,5)
begin
	declare l_value 	decimal (15,5);

	-- short circuit if commodity provided is the default currency
	if p_guid = get_default_currency_guid() then
		return 1;
	end if;

	-- try to play nicely with other procedures
	do is_locked('splits, accounts, transactions', 'WAIT');

	-- set default date
	set p_date = ifnull(p_date, current_timestamp);

	select	price
	into 	l_value
	from
	(
		select 	distinct round(value_num/value_denom, 5) as price,
			date as date
		from 	prices 		
		where 	commodity_guid = p_guid
			and date <= p_date
			-- and date > date_add(p_date, interval - 7 day)
		
		union

		-- include data from actual transactions
		select	distinct 	
				abs(
					round(
						(splits.value_num/splits.value_denom) / (splits.quantity_num/splits.quantity_denom)
					, 5)
				),
				transactions.post_date
		from
			splits splits
			join accounts accounts 
				on splits.account_guid = accounts.guid
			join transactions transactions 
				on splits.tx_guid = transactions.guid
		where 
			accounts.commodity_guid = p_guid
			and splits.value_num != splits.quantity_num
			and splits.quantity_num != 0
			and transactions.currency_guid = get_commodity_currency(p_guid)
			and transactions.post_date <= p_date
			-- and transactions.post_date > date_add(p_date, interval - 7 day)
	) prices

	order by prices.date desc
	limit 	1;

	return l_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the latest date a price was added 
drop function if exists get_commodity_latest_date;
//
create function get_commodity_latest_date
	(
		p_guid			varchar(32)
	)
	returns 			timestamp
begin
	declare l_date 			timestamp;

	-- try to play nicely with other procedures
	do is_locked('splits, accounts, transactions', 'WAIT');

	select distinct max(date)
	into 	l_date
	from
	(
		select 	prices.date as "date"
		from 	prices 
		where 	commodity_guid = p_guid
			and date <= current_timestamp
	
		union

		select transactions.post_date
		from
			splits splits
			join accounts accounts 
				on splits.account_guid = accounts.guid
			join transactions transactions 
				on splits.tx_guid = transactions.guid
		where 
			accounts.commodity_guid = p_guid
			and splits.value_num != splits.quantity_num
			and splits.quantity_num != 0
			and transactions.currency_guid = get_commodity_currency(p_guid)
			and transactions.post_date <= current_timestamp
	) dates
	limit 	1;

	-- return convert_tz( l_date, get_constant('Default timezone'), 'UTC');
	return round_timestamp(l_date);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the earliest date a price was added 
drop function if exists get_commodity_earliest_date;
//
create function get_commodity_earliest_date
	(
		p_guid			varchar(32)
	)
	returns 			timestamp
begin
	declare l_date 			timestamp;

	-- try to play nicely with other procedures
	do is_locked('splits, accounts, transactions', 'WAIT');

	select distinct min(date)
	into 	l_date
	from
	(
		select 	prices.date as "date"
		from 	prices 
		where 	commodity_guid = p_guid
			and date <= current_timestamp
	
		union

		select transactions.post_date
		from
			splits splits
			join accounts accounts 
				on splits.account_guid = accounts.guid
			join transactions transactions 
				on splits.tx_guid = transactions.guid
		where 
			accounts.commodity_guid = p_guid
			and splits.value_num != splits.quantity_num
			and splits.quantity_num != 0
			and transactions.currency_guid = get_commodity_currency(p_guid)
			and transactions.post_date <= current_timestamp
	) dates
	limit 	1;

	-- return convert_tz( l_date, get_constant('Default timezone'), 'UTC');
	return round_timestamp(l_date);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] posts a new commodity to the gnucash commodities table
drop function if exists post_commodity;
//
create function post_commodity
	(
		p_symbol	varchar(2048),
		p_type		varchar(2048),
		p_fullname	varchar(2048),	
		p_isin		varchar(2048),
		p_fraction	int(11),
		p_quote_flag	int(11),
		p_quote_source	varchar(2048),
		p_quote_tz	varchar(2048)
	)
	returns varchar(32)
begin
	declare l_guid		varchar(32);

	-- call log(concat('DEBUG : START post_commodity(', 
	--		ifnull(p_symbol, 'null'), ',', 
	--		ifnull(p_type, 'null'), ',', 
	--		ifnull(p_fullname, 'null'), ',', 
	--		ifnull(p_isin, 'null'), ',', 
	--		ifnull(p_fraction, 'null'), ',', 
	--		ifnull(p_quote_flag, 'null'), ',', 
	--		ifnull(p_quote_source, 'null'), ',', 
	--		ifnull(p_quote_tz, 'null'), ')'
	--	));

	-- try to play nicely with other procedures
	do is_locked('commodities', 'WAIT');

	-- initialise
	set p_type 		= upper(p_type);
	set p_symbol 		= upper(p_symbol);
	set p_quote_flag 	= ifnull( p_quote_flag, 0);
	if p_quote_flag 	!= 0 then
		set p_quote_flag = 1;
	end if;
	set p_quote_source 	= lower(p_quote_source);

	case p_type
		when 'CURRENCY' then
			set p_quote_source = 'currency';
			set p_fraction = ifnull(p_fraction,100);
			set p_quote_tz = '';
		when 'EUREX' then
			set p_quote_source = ifnull(p_quote_source, 'europe');
			set p_fraction = 1;
		else
			set p_quote_source = lower(p_quote_source);
			set p_fraction = 1;
	end case;

	-- sanity check
	if	p_fullname is null
		or p_symbol is null
		or p_type is null
		or p_type not in ('CURRENCY', 'EUREX', 'AMEX', 'FUND', 'NASDAQ', 'NYSE')
		or (p_quote_flag = 1 and p_quote_source is null)  -- quote source is enumerated in the GnuCash GUI, but I dont know what the valid values are
		or exists_commodity(p_symbol)
	then
		return null;
	end if;

	if gnc_lock('commodities') then
		set l_guid = new_guid();

		insert into commodities
			(	guid, 
				namespace, 
				mnemonic, 
				fullname,
				cusip, 
				fraction,
				quote_flag, 
				quote_source, 
				quote_tz
			)
		values
			(	l_guid, 
				p_type,
				p_symbol,
				p_fullname,
				p_isin,
				p_fraction,
				p_quote_flag,
				p_quote_source,
				p_quote_tz
			);
		call log( concat('INFORMATION : Added commodity ' , l_guid , ' "', p_symbol ,'"' ));

		call gnc_unlock('commodities') ;

	end if;

	-- call log('DEBUG : END post_commodity');	

	return l_guid;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] converts a value from one currency/commodity unit to another, using the latest exchange rate valid on a given date
-- relies entirely on exchange rates in the GnuCash database, so won't work as a general FX calculator
-- performs 1 or 2 conversions only; ie can do USD->GBP or GBP->USD (1 conversion) if either are quoted for the day requested, or 
-- X->GBP if X is quoted in USD, or X->USD if X is quoted in GBP (2 conversions) and both relevant quotes are available
drop function if exists convert_value;
//
create function convert_value
	(
		p_value			decimal(20,6),
		p_from			varchar(32),
		p_to			varchar(32),
		p_date			timestamp
	)
	returns 			decimal (20,6)
begin
	declare l_conversion_rate	decimal(20,6);

	-- call log(concat('DEBUG : START convert_value(', ifnull(p_value, 'null'), ',', ifnull(p_from, 'null'), ',', ifnull(p_to, 'null'), ',', ifnull(p_date, 'null'), ')' ));

	-- return null or 0 if value is null or zero
	if ifnull(p_value, 0) = 0 
	then
		return p_value;
	end if;

	-- assume p_from and p_to are GBP if null
	set p_from = ifnull(p_from, get_default_currency_guid() );
	set p_to = ifnull(p_to, get_default_currency_guid() );
	
	-- short circuit where p_from = p_to (or both were null)
	if p_from = p_to 
	then
		return p_value;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices, commodities', 'WAIT');

	-- assume date is "now" if null
	set p_date = round_timestamp(ifnull(p_date, current_timestamp));

	-- 1. check to see if part of the calculation has been done already
	-- code removed; not clear when this would be useful

	-- 2. check if p_from is quoted in p_to units (or vice-versa) allowing a direct (or inverse) conversion
	if l_conversion_rate is null then

		if get_commodity_currency(p_from) = p_to then

			set l_conversion_rate = get_commodity_price(p_from, p_date);

		elseif get_commodity_currency(p_to) = p_from then

			set l_conversion_rate = 1 / get_commodity_price(p_to, p_date);

		end if;

	end if;

	-- 3. check if there is a conversion rate from whatever p_from is quoted in to whatever p_to is quoted in
	-- for example, converting a GBP quoted share price in USD
	if l_conversion_rate is null then

		-- 3.1 find out conversion rate from whatever p_from is quoted in to whatever p_to is quoted in 
		-- ie IUKD is quoted in GBP, USD is quoted in GBP and I want IUKD quoted in USD :
		if get_commodity_currency(p_from) = get_commodity_currency(p_to) then

			-- ie (IUKD->GBP rate) / (USD->GBP rate)
			set l_conversion_rate = get_commodity_price(p_from, p_date) / get_commodity_price(p_to, p_date) ;

		-- or vice-versa
		-- ie USDV is quoted in USD, USD is quoted in GBP and I want USDV quoted in GBP :
		elseif get_commodity_currency( get_commodity_currency(p_from) ) = p_to then

			-- ie (USDV->USD rate) * (USD->GBP rate)
			set l_conversion_rate = get_commodity_price(p_from, p_date) * get_commodity_price(get_commodity_currency(p_from), p_date) ;

		end if;

	end if;

	-- 4. do conversion
	-- call log('DEBUG : END convert_value');
	if l_conversion_rate is not null then
		return round(p_value * l_conversion_rate, 6);
	end if;

	-- 5. if we've got this far then conversion couldnt be done
	return null;

end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the latest denominator (fractions of a commodity unit) in which a price is quoted
-- this function intentionally ignores commodity values in the splits table (unlike get_commodity_price)
-- because at the moment it is only used to update price quotes
drop function if exists get_commodity_latest_denom;
//
create function get_commodity_latest_denom
	(
		p_guid			varchar(32)
	)
	returns 			bigint(20)
begin
	declare l_denom 		bigint(20);

	-- try to play nicely with other procedures
	do is_locked('prices, commodities', 'WAIT');

	select 	value_denom
	into 	l_denom
	from 	prices 
	where 	commodity_guid = p_guid
	order by date desc
	limit 	1;

	-- if that didn't work, use the commodities table (which defines fractional currency units)
	if l_denom is null and is_currency(p_guid) then
		select 	fraction
		into 	l_denom
		from 	commodities
		where 	guid = p_guid
		limit 	1;
	end if;

	-- you could also use the splits table if all else fails (unimplemented)

	return l_denom;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the guid of the accounts (home) commodity account 
-- this may be a currency, or a stock, for example
drop function if exists get_account_commodity;
//
create function get_account_commodity
	(
		p_guid varchar(32)
	)
	returns varchar(32)
begin
	declare l_guid varchar(32);

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	commodity_guid 
	into 	l_guid
	from 	accounts 
	where 	guid = p_guid 
	limit 	1;

	return trim(l_guid);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] the performance (as %) of a commodity over the period (in days) specified
-- for use in determining market price drops or gains
-- you can compare in a given currency, or by default (p_currency=null) just use the native currency of the holding 
drop function if exists get_commodity_performance;
//
create function get_commodity_performance
	(
		p_guid			varchar(32), 
		p_days			bigint(20),
		p_currency		varchar(32)
	)
	returns				decimal(7,2)
begin
	declare l_current_value 	decimal(15,5);
	declare l_previous_value 	decimal(15,5);

	set p_days = - ifnull( abs(p_days), 0);

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	-- get values in commodity native currency
	set l_current_value = get_commodity_price(p_guid, null);
	set l_previous_value = get_commodity_price(p_guid, date_add(current_timestamp, interval p_days day));

	-- convert to specified currency
	if 	p_currency is not null 
		and exists_commodity(p_currency)
		and get_commodity_currency(p_guid) != p_currency 
	then
		set l_current_value = convert_value(l_current_value, get_commodity_currency(p_guid), p_currency, null);
		set l_previous_value = convert_value(l_previous_value, get_commodity_currency(p_guid), p_currency, date_add(current_timestamp, interval p_days day));

	end if;

	return ((l_current_value - l_previous_value) * 100) /  l_previous_value;

end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] gets extreme HIGH or LOW for commodity in previous p_days days before p_date
-- returns value in a given currency, or by default (p_currency=null) just uses the native currency of the holding  
drop function if exists get_commodity_extreme_price;
//
create function get_commodity_extreme_price
	(
		p_guid			varchar(32), 
		p_mode			varchar(10), -- 'HIGH' or 'LOW'
		p_date			timestamp,
		p_days			bigint(20),
		p_currency		varchar(32)
	)
	returns				decimal(20,6)
begin
	declare l_value		decimal(20,6);
	declare l_date		timestamp;

	if not exists_commodity(p_guid) then
		return null;
	end if;

	-- set defaults and standardise
	set p_days = abs(ifnull(p_days, 0));
	set p_date = ifnull(p_date, current_date);

	-- check sanity
	if 	p_days <= 0
		or p_mode is null
		or p_mode not in ('HIGH', 'LOW')
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	case p_mode
	when 'HIGH' then

		select 	max(value_num/value_denom),
			round_timestamp(date)
		into 	l_value, 
			l_date
		from 	prices
		where 	commodity_guid = p_guid
		and 	datediff(p_date, round_timestamp(date)) <= p_days;

	when 'LOW' then

		select 	min(value_num/value_denom),
			round_timestamp(date)
		into 	l_value, 
			l_date
		from 	prices
		where 	commodity_guid = p_guid
		and 	datediff(p_date, round_timestamp(date)) <= p_days;

	end case;

	-- convert to specified currency if requested
	if 	p_currency is not null
		and p_currency != get_commodity_currency(p_guid)
	then
		set l_value = convert_value(
					l_value,
					get_commodity_currency(p_guid), 
					p_currency, 
					l_date);
	end if;

	return l_value;
	
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] gets most recent date when the price for a commodity was as HIGH or LOW as at p_date (default, 'now')
drop function if exists get_commodity_extreme_date;
//
create function get_commodity_extreme_date
	(
		p_guid			varchar(32), 
		p_mode			varchar(10), -- 'HIGH' or 'LOW'
		p_date			timestamp
	)
	returns				timestamp
begin
	declare l_date		timestamp;

	if not exists_commodity(p_guid) then
		return null;
	end if;

	-- set defaults and standardise
	set p_date = ifnull(p_date, current_date);

	-- check sanity
	if 	p_mode is null
		or p_mode not in ('HIGH', 'LOW')
		or datediff(p_date, get_commodity_latest_date(p_guid)) > ifnull(get_variable('Ignore extremes'),7) -- dont bother calculating for commodities with old quotes
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	case p_mode
	when 'HIGH' then

		select 	date	
		into 	l_date
		from	prices
		where 	commodity_guid = p_guid
		and 	date < least(p_date, get_commodity_latest_date(p_guid))
		and 	value_num/value_denom >= get_commodity_price(p_guid, p_date)
		order by date desc
		limit 1;

	when 'LOW' then

		select 	date
		into 	l_date
		from 	prices
		where 	commodity_guid = p_guid
		and 	date < least(p_date, get_commodity_latest_date(p_guid))
		and 	value_num/value_denom <= get_commodity_price(p_guid, p_date)
		order by date desc
		limit 1;

	end case;

	-- return convert_tz( l_date, get_constant('Default timezone'), 'UTC');
	return round_timestamp(l_date);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the SMA (simple moving average) of a commodity
-- potentially inaccurate where prices are missing or doubled up for a date in the specified range
drop function if exists get_commodity_sma;
//
create function get_commodity_sma
	(
		p_guid			varchar(32),
		p_days			smallint,
		p_date			timestamp
	)
	returns				decimal(15,5)
begin
	declare l_sma			decimal(15,5) default null;
	declare l_earliest_date		timestamp;
	declare l_latest_date		timestamp;
	declare	l_variable_name		varchar(250);

	-- call log( concat('DEBUG : START get_commodity_sma(', ifnull(p_guid, 'null'), ',', ifnull(p_days, 'null'), ',', ifnull(p_date, 'null'), ')'));

	if not exists_commodity(p_guid) then
		return null;
	end if;

	-- the price of the default currency (against itself) is always 1
	if p_guid = get_default_currency_guid() then
		return 1;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices, commodity_attributes', 'WAIT');

	-- initialise
	set p_date		= round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day) )); 
	set p_days 		= abs(ifnull(p_days, 26)); 
	set l_earliest_date 	= get_commodity_earliest_date(p_guid);
	set l_latest_date 	= get_commodity_latest_date(p_guid);
	set l_variable_name 	= concat('sma(', p_days, ')');

	-- abandon calculation of there is no price data for the date range specified
	if 	l_earliest_date is null 
		or l_latest_date is null 
		or p_date < l_earliest_date 
		or p_date > l_latest_date 
	then
		return null;
	end if;

	-- use pre-calculated value if available
	if 	get_variable('Recalculate') = 'N'
		and exists_commodity_attribute(p_guid, l_variable_name, p_date)
	then
		set l_sma = get_commodity_attribute(p_guid, l_variable_name, p_date);
	else

		-- TODO : deal with cases when there is >1 price per day
		select 	round( avg(value_num/value_denom),6)
		into	l_sma
		from	prices
		where	commodity_guid = p_guid
		and 	date <= p_date
		and 	date > date_add(p_date, interval - p_days day);

		-- note : this function is called by post_commodity_price which is called by post_commodity_attribute. Recursive function calls are not permitted in MySQL
		if 	l_sma is not null
		and 	not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
		then
			call post_commodity_attribute(p_guid, l_variable_name, p_date, l_sma);
		end if;

	end if;

	-- call log('DEBUG : END get_commodity_sma');

	return l_sma;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the EMA (exponential moving average) of a commodity
-- potentially inaccurate where prices are missing for a date in the specified range
drop function if exists get_commodity_ema;
//
create function get_commodity_ema
	(
		p_guid			varchar(32),
		p_days			smallint,
		p_date			timestamp
	)
	returns 			decimal(15,5)
begin
	declare l_ema 			decimal(15,5);
	declare l_multiplier		decimal(15,5);
	declare l_date			timestamp;
	declare l_earliest_date		timestamp;
	declare l_latest_date		timestamp;
	declare	l_variable_name		varchar(250);
	declare l_price			decimal(15,5);

	-- call log( concat('DEBUG : START get_commodity_ema(', ifnull(p_guid, 'null'), ',', ifnull(p_days, 'null'), ',', ifnull(p_date, 'null'), ')'));

	if not exists_commodity(p_guid) then
		return null;
	end if;

	-- the price of the default currency (against itself) is always 1
	if p_guid = get_default_currency_guid() then
		return 1;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices, commodity_attributes', 'WAIT');

	-- initialise
	set p_days 		= abs(ifnull(p_days, 26));
	set p_date 		= round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day) )) ;
	set l_earliest_date 	= get_commodity_earliest_date(p_guid);
	set l_latest_date 	= get_commodity_latest_date(p_guid);
	set l_date 		= p_date;
	set l_variable_name 	= concat('ema(', p_days, ')');

	-- abandon calculation of there is no price data for the date specified
	if 	l_earliest_date is null 
		or l_latest_date is null 
		or date_add(p_date, interval - p_days day) < l_earliest_date 
		or p_date > l_latest_date 
	then
		return null;
	end if;

	-- 1. Find latest EMA calculated at or before the date specified (there may be none) as a starting point
	-- only look back get_variable('EMA initialisation') days before requested date
	while 	l_date >= greatest(l_earliest_date, date_add(p_date, interval - get_variable('EMA initialisation') day ))
		and l_ema is null --  ie short circuit when value found
	do
		if 	get_variable('Recalculate') = 'N'
			and exists_commodity_attribute(p_guid, l_variable_name, l_date)
		then
			set l_ema = get_commodity_attribute(p_guid, l_variable_name, l_date); 
		else
			set l_date = round_timestamp(date_add(l_date, interval - 1 day)); -- go back one day to look again
		end if;
	end while;

	-- 2. if the latest SMA isnt the one we're looking for, we'll need to calculate it ...
	if l_date < least(p_date, l_latest_date)
	then
		-- call log( concat('DEBUG : Preparing to calculate new emas from l_date=', ifnull(l_date, 'null')));
		-- 3. if l_ema is null, calculate the starting point (which is actually an sma)
		if l_ema is null then
			set l_ema = get_commodity_sma(p_guid, p_days, l_date);
		end if;

		-- get appropriate SMA multiplier
		set l_multiplier = 2 / ( p_days + 1 ); 

		-- 4. Wind forward from l_date to p_date, calculating ema as you go
		repeat
			set l_date = date_add(l_date, interval 1 day);
			set l_price = get_commodity_price(p_guid, l_date);

			if l_price is not null then
				set l_ema = 	(l_price * l_multiplier)
							+
						(l_ema * (1 - l_multiplier));
				
				-- store the result for the next time, if possible and desirable
				if 	l_ema is not null 
					and not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				then
					call post_commodity_attribute(p_guid, l_variable_name, l_date, l_ema);
				end if;
			end if;

		until l_date >= least(p_date, l_latest_date)
		end repeat;

	end if;

	-- it is possible that we dont have enough data to return EMA for the date requested (l_latest_date < p_date)
	if l_date != p_date then
		set l_ema = null;
	end if;

	-- call log('DEBUG : END get_commodity_ema');

	return l_ema;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the PPO (percentage price oscillator) of a commodity (a %age version of the MACD)
-- (("12-day commodity EMA" - "26-day commodity EMA") * 100 / "26-day commodity EMA")- "9-day EMA of the 12-26 EMA line")
-- very labour intensive to calculate the first time, and only useful in a series (which is automatically stored)
-- results are only likely to be accurate if you have a *full* dataset for at least 100 days
drop procedure if exists get_commodity_ppo;
//
create procedure get_commodity_ppo
	(
		in p_guid			varchar(32), 	-- commodity guid
		in p_date			timestamp, 	-- date for which PPO is required

		out p_ppo_line			decimal(6,3),
		out p_ppo_signal_line		decimal(6,3),
		out p_ppo_histogram		decimal(6,3)
	)
procedure_block : begin
	declare l_counter 				int default 0;
	declare l_date					timestamp;
	declare l_multiplier				decimal(15,5);	
	declare l_earliest_date				timestamp;
	declare l_latest_date				timestamp;
	declare l_ppo_signal_line			decimal(6,3);
	declare l_short_ema				decimal(6,3);
	declare l_long_ema				decimal(6,3);
	declare l_ppo_line_variable_name		varchar(100);	
	declare l_ppo_signal_line_variable_name		varchar(100);
	declare l_ppo_histogram_variable_name		varchar(100);
	declare l_short_ema_days			int;
	declare l_long_ema_days				int;
	declare l_signal_days				int;

	-- call log( concat('DEBUG : START get_commodity_ppo(', ifnull(p_guid, 'null'), ',', ifnull(p_date, 'null'),')'));

	if 	not exists_commodity(p_guid) 
		or p_guid = get_default_currency_guid()
	then
		-- call log( concat('DEBUG : leave procedure_block (1)'));
		leave procedure_block;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices, commodity_attributes', 'WAIT');

	-- set defaults
	set p_date 		= round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day) ));
	set l_date 		= p_date;
	set l_short_ema_days 	= ifnull(get_variable('Short EMA days'), 12);
	set l_long_ema_days	= ifnull(get_variable('Long EMA days'), 26);
	set l_signal_days 	= ifnull(get_variable('Signal days'), 9);
	set l_earliest_date 	= get_commodity_earliest_date(p_guid); 
	set l_latest_date 	= get_commodity_latest_date(p_guid);
	set l_ppo_line_variable_name 			= concat('ppo_line(', 		l_short_ema_days, ',', l_long_ema_days,')');	
	set l_ppo_signal_line_variable_name 		= concat('ppo_signal_line(', 	l_short_ema_days, ',', l_long_ema_days,',', l_signal_days, ')');
	set l_ppo_histogram_variable_name 		= concat('ppo_histogram(', 	l_short_ema_days, ',', l_long_ema_days,',', l_signal_days,')');

	-- abandon calculation of there is no price data for the date specified
	if 	l_earliest_date is null 
		or l_latest_date is null 
		or p_date < l_earliest_date 
		or p_date > l_latest_date
	then
		-- call log( concat('DEBUG : leave procedure_block (2)'));
		leave procedure_block;
	end if;

	-- call log( concat('DEBUG : l_date =', ifnull(date_format(l_date, '%Y-%m-%d'), 'null') ));
	-- call log( concat('DEBUG : l_earliest_date =', ifnull(date_format(l_earliest_date, '%Y-%m-%d'), 'null') ));
	-- call log( concat('DEBUG : p_date =', ifnull(date_format(p_date, '%Y-%m-%d'), 'null') ));

	-- 1. Find latest PPO calculated at or before the date specified (there may be none) as a starting point
	-- go back a max of 'EMA initialisation' days (default is 100)
	while 	l_date >= greatest(	date_add(l_earliest_date, interval l_signal_days day),
					date_add( p_date, interval - get_variable('EMA initialisation') + 1 day )
				)
		--  short circuit when all values found
		and (
			p_ppo_line 		is null 
			or p_ppo_signal_line 	is null
			or p_ppo_histogram 	is null
		) 
	do

		if 	get_variable('Recalculate') = 'N' then

			if exists_commodity_attribute( p_guid, l_ppo_line_variable_name, l_date) then	
				set p_ppo_line = get_commodity_attribute( p_guid, l_ppo_line_variable_name, l_date);
			end if;
			
			if exists_commodity_attribute( p_guid, l_ppo_signal_line_variable_name, l_date) then	
				set p_ppo_signal_line = get_commodity_attribute( p_guid, l_ppo_signal_line_variable_name, l_date);
			end if;

			if exists_commodity_attribute( p_guid, l_ppo_histogram_variable_name, l_date) then	
				set p_ppo_histogram = get_commodity_attribute( p_guid, l_ppo_histogram_variable_name, l_date);
			end if;

			-- call log( concat('DEBUG : [search] l_date =', ifnull(l_date, 'null'), '; p_ppo_line =', ifnull(p_ppo_line, 'null') ));
			-- call log( concat('DEBUG : [search] l_date =', ifnull(l_date, 'null'), '; p_ppo_signal_line =', ifnull(p_ppo_signal_line, 'null') ));
			-- call log( concat('DEBUG : [search] l_date =', ifnull(l_date, 'null'), '; p_ppo_histogram =', ifnull(p_ppo_histogram, 'null') ));

		end if;

		-- go back one day to look again if any one value cannot be found
		if 		p_ppo_line 		is null 
			or 	p_ppo_signal_line	is null
			or 	p_ppo_histogram 	is null
		then
			set l_date = round_timestamp( date_add(l_date, interval -1 day));
		end if;

	end while;

	-- 2. if the latest PPO isnt the one we're looking for, we'll need to calculate it ...
	if 	l_date < least(p_date, l_latest_date)
	then
		-- call log( concat('DEBUG : [calc] l_date =', ifnull(date_format(l_date, '%Y-%m-%d'), 'null') ));

		-- set appropriate EMA multiplier
		set l_multiplier = 2 / ( l_signal_days + 1 ); 

		-- 3. wind forward through time calculating values as you go
		set l_counter = 1;

		repeat
			-- set next day
			set l_date = date_add( l_date, interval 1 day);

		-- while l_date <= least(p_date, l_latest_date)
		-- do
			set l_short_ema = get_commodity_ema( p_guid, l_short_ema_days, l_date);	
			set l_long_ema = get_commodity_ema( p_guid, l_long_ema_days, l_date);
			
			if 	l_short_ema is not null
				and l_long_ema is not null
			then
				set p_ppo_line = 100 * ( (l_short_ema - l_long_ema) / l_long_ema );
			end if;
			
			-- call log( concat('DEBUG : [calc] l_date =', ifnull(l_date, 'null'), '; p_ppo_line =', ifnull(p_ppo_line, 'null') ));

			-- post newly calculated values
			if 	not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				and p_ppo_line is not null
			then
				call delete_commodity_attribute( p_guid, l_ppo_line_variable_name, l_date);
				call post_commodity_attribute( p_guid, l_ppo_line_variable_name, l_date, p_ppo_line);
			end if;

			-- calculate signal line as EMA (initialised as SMA) of ppo_line
			if 	p_ppo_line is not null
			then
				if 	p_ppo_signal_line is not null 
				then
					-- call log('DEBUG : calculating p_ppo_signal_line running EMA');

					-- calculate (running) EMA based in previous p_ppo_signal_line
					set p_ppo_signal_line = ( p_ppo_line * l_multiplier )
								+
								( p_ppo_signal_line * (1 - l_multiplier));

				else

					-- call log('DEBUG : calculating p_ppo_signal_line initialising SMA');

					-- calculate initialising SMA
					if l_counter <= l_signal_days then
						set l_ppo_signal_line = ifnull(l_ppo_signal_line,0) + p_ppo_line;
					end if;
					if l_counter = l_signal_days then
						set p_ppo_signal_line = l_ppo_signal_line / l_signal_days;
					end if;

				end if;
			end if;

			-- log calculated signal line, and calculate and log difference twixt both
			if 	p_ppo_signal_line is not null then
				
				if not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				then
					call delete_commodity_attribute( p_guid, l_ppo_signal_line_variable_name, l_date);
					call post_commodity_attribute( p_guid, l_ppo_signal_line_variable_name, l_date, p_ppo_signal_line);
				end if;

				set p_ppo_histogram = p_ppo_line - p_ppo_signal_line;

				if not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				then
					call delete_commodity_attribute( p_guid, l_ppo_histogram_variable_name, l_date);
					call post_commodity_attribute( p_guid, l_ppo_histogram_variable_name, l_date, p_ppo_histogram);
				end if;

			end if;

			-- set next day
			-- set l_date = date_add( l_date, interval 1 day);
			set l_counter = l_counter + 1;

		-- end while; -- while l_date <= least(p_date, l_latest_date)

		until l_date >= least(p_date, l_latest_date)
		end repeat;

	end if; -- if 	l_date < least(p_date, l_latest_date)

	-- it is possible that we dont have enough data to return PPO for the date requested (l_latest_date < p_date)
	-- if date_add(l_date, interval -1 day) != p_date then
	if l_date != p_date then
		set p_ppo_line = null;
		set p_ppo_signal_line = null;
		set p_ppo_histogram = null;
	end if;

	-- call log('DEBUG : END get_commodity_ppo');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] returns the SO (stochastic oscillator) of a commodity
drop procedure if exists get_commodity_so;
//
create procedure get_commodity_so
	(
		in p_guid			varchar(32), 	-- commodity guid
		in p_date			timestamp, 	-- date for which SO is required

		out p_so_fast_line		decimal(6,3), -- unsmoothed so
		out p_so_slow_line		decimal(6,3),
		out p_so_signal_line		decimal(6,3)
	)
procedure_block : begin
	declare l_days				int;
	declare l_period			int;
	declare l_date				timestamp;
	declare l_high				decimal(20,6);
	declare l_low				decimal(20,6);
	declare l_earliest_date			timestamp;
	declare l_latest_date			timestamp;
	declare l_count				int;
	declare	l_fast_variable_name		varchar(250);
	declare	l_slow_variable_name		varchar(250);
	declare	l_signal_variable_name		varchar(250);

	-- call log( concat('DEBUG : START get_commodity_so(', ifnull(p_guid, 'null'), ',', ifnull(p_date, 'null'), ')'));
	
	if 	not exists_commodity(p_guid) 
		or p_guid = get_default_currency_guid()	
	then
		leave procedure_block;
	end if;

	-- try to play nicely with other procedures
	do is_locked('prices, commodity_attributes', 'WAIT');

	-- set defaults
	set p_date 			= round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day) ));
	set l_days 			= 3; -- need a 3-day sma signal line
	set l_period 			= ifnull(get_variable('Stochastic oscillator period'), 14);
	set l_date 			= p_date;
	set l_earliest_date 		= get_commodity_earliest_date(p_guid); -- the earliest date for which a quote is available for this commodity
	set l_latest_date 		= get_commodity_latest_date(p_guid);
	set l_fast_variable_name 	= concat('so_fast_line(', l_period, ')');
	set l_slow_variable_name 	= concat('so_slow_line(', l_period, ')');
	set l_signal_variable_name 	= concat('so_signal_line(', l_period, ')');

	-- abandon calculation of there is no price data for the date specified
	if 	l_earliest_date is null 
		or l_latest_date is null 
		or p_date < l_earliest_date 
		or p_date > l_latest_date 
	then
		leave procedure_block;
	end if;

	-- 1. Find latest SO calculated at or before the date specified (there may be none) as a starting point
	while 	l_date >= greatest( 	date_add(l_earliest_date, interval l_days day), 
					date_add( p_date, interval - get_variable('EMA initialisation') + 1 day ) 
					)
		and (
			p_so_fast_line 		is null 
			or p_so_slow_line 	is null
			or p_so_signal_line 	is null
		) --  ie short circuit when all values found
	do
		if get_variable('Recalculate') = 'N' then

			if exists_commodity_attribute( p_guid, l_fast_variable_name, l_date) then	
				set p_so_fast_line = get_commodity_attribute( p_guid, l_fast_variable_name, l_date);
			end if;

			if exists_commodity_attribute( p_guid, l_slow_variable_name, l_date) then	
				set p_so_slow_line = get_commodity_attribute( p_guid, l_slow_variable_name, l_date);
			end if;

			if exists_commodity_attribute( p_guid, l_signal_variable_name, l_date) then	
				set p_so_signal_line = get_commodity_attribute( p_guid,  l_signal_variable_name, l_date);
			end if;

		end if;

		-- go back one day to look again if any one value cannot be found
		if 	p_so_fast_line 		is null 
			or p_so_slow_line 	is null
			or p_so_signal_line 	is null
		then
			set l_date = round_timestamp(date_add(l_date, interval -1 day));
		end if;

	end while;

	-- 2. if the latest SO isnt the one we're looking for, we'll need to calculate it ...
	-- by this stage l_date is either the latest date for which SO has been calculated, or null, indicating it has never been calculated 
	if 	l_date < least(p_date, l_latest_date)
	then

		-- tables to hold running averages
		drop temporary table if exists so_fast_tally;
		create temporary table so_fast_tally (
			date			timestamp,
			value			decimal(6,3)
		);

		drop temporary table if exists so_slow_tally;
		create temporary table so_slow_tally (
			date			timestamp,
			value			decimal(6,3)
		);

		-- 3. wind forward through time calculating values as you go
		-- while l_date <= least(p_date, l_latest_date)
		-- do
		repeat
			-- set next day
			set l_date = date_add( l_date, interval 1 day);

			set l_low = get_commodity_extreme_price(p_guid, 'LOW', l_date, l_days, null);
			set l_high = get_commodity_extreme_price(p_guid, 'HIGH', l_date, l_days, null);

			set p_so_fast_line = 100 * ( 	( get_commodity_price(p_guid, l_date) - l_low) 
							/ 
							(l_high - l_low) 
						);

			-- post newly calculated value
			if 	p_so_fast_line is not null
				and not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
			then
				call delete_commodity_attribute( p_guid, l_fast_variable_name, l_date);
				call post_commodity_attribute( p_guid, l_fast_variable_name, l_date, p_so_fast_line);
			end if;

			-- keep running tallies up to date
			insert into so_fast_tally (date, value) values (l_date, p_so_fast_line);
			delete from so_fast_tally where date <= date_add(l_date, interval - l_days day);

			select 	count(*)
			into 	l_count
			from 	so_fast_tally;

			-- calculate p_so_slow_line as SMA of p_so_fast_line
			if l_count >= l_days then

				select 	avg(value)
				into 	p_so_slow_line
				from 	so_fast_tally;

				if 	p_so_slow_line is not null
					and not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				then
					call delete_commodity_attribute( p_guid, l_slow_variable_name, l_date);
					call post_commodity_attribute( p_guid, l_slow_variable_name, l_date, p_so_slow_line );
				end if;

				insert into so_slow_tally (date, value) values (l_date, p_so_slow_line);
			
			end if;

			delete from so_slow_tally where date <= date_add(l_date, interval - l_days day);

			select 	count(*)
			into 	l_count
			from 	so_slow_tally;

			-- calculate p_so_signal_line as SMA of p_so_slow_line
			if l_count >= l_days then

				select 	avg(value)
				into 	p_so_signal_line
				from 	so_slow_tally;

				if 	p_so_signal_line is not null
					and not is_locked('post_commodity_attribute,commodity_attribute', 'NOWAIT')
				then
					call delete_commodity_attribute( p_guid, l_signal_variable_name, l_date);
					call post_commodity_attribute( p_guid, l_signal_variable_name, l_date, p_so_signal_line );
				end if;
			end if;

		-- end while; -- while l_date <= least(p_date, l_latest_date)
		until l_date >= least(p_date, l_latest_date)
		end repeat;

	end if; -- if l_date < least(p_date, l_latest_date)

	-- it is possible that we dont have enough data to return SO for the date requested (l_latest_date < p_date)
	-- if date_add(l_date, interval -1 day) != p_date then
	if l_date != p_date then
		set p_so_fast_line = null;
		set p_so_slow_line = null;
		set p_so_signal_line = null;
	end if;

	-- call log('DEBUG : END get_commodity_so');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] Get a commodity BUY/SELL signal
-- Uses percentage price osciallator (PPO), stochastic osciallator (SO) and price extremes to make a buy or sell recommendation, based on your preset target allocations
-- *Highly experimental* and should not be used to make actual buy or sell decisions.
-- THE AUTHOR HAS NO RESPONSIBILITY FOR DECISIONS MADE BASED IN THIS FUNCTION, OR ERRORS MADE BY THIS FUNCTION!
drop function if exists get_signal;
//
create function get_signal
	(
		p_guid			varchar(32), -- commodity being watched
		p_unit_change		decimal(20,6), -- -ve number means sell, +ve : buy (absolute value is irrelevant)
		p_predicted_gain	decimal(20,6), -- +ve, -ve or zero; used to filter out loss making SELL signals (absolute value is irrelevant)
		p_date			timestamp -- defaults to yesterday if null
	)
	returns 	text
begin
	declare l_report 		text default null; 
	declare l_verbose_report 	text default null;
	declare l_conclusion		varchar(100); 
	declare l_date			timestamp;
	declare l_vote			decimal(6,3);
	declare l_max_vote  		decimal(6,3);
	declare l_strong_vote 		decimal(6,3);
	declare l_mild_vote 		decimal(6,3);
	declare l_observation 		varchar(100);
	declare l_days_back		int;

	-- SO variables
	declare l_fast_so_line 		decimal(6,3);
	declare l_slow_so_line		decimal(6,3);
	declare l_signal_line		decimal(6,3);

	-- PPO variables
	declare l_ppo_line 			decimal(6,3);
	declare l_ppo_signal_line		decimal(6,3);
	declare l_ppo_histogram			decimal(6,3);
	declare l_short_ema_days		int;
	declare l_long_ema_days			int;
	declare l_signal_days			int;
	declare l_gradient_sensitivity		decimal(2,1);
	declare l_ppo_line_gradient		decimal(4,3);
	declare l_ppo_histogram_gradient	decimal(4,3);
	declare l_previous_ppo_line 		decimal(6,3) default null;
	declare l_previous_ppo_histogram	decimal(6,3) default null;

	-- extremes variables
	declare l_days_since_high		int;
	declare l_days_since_low		int;

	-- call log( concat('DEBUG : START get_signal(', ifnull(p_guid, 'null'), ',', ifnull(p_unit_change, 'null'), ',',  ifnull(p_predicted_gain, 'null'), ',', ifnull(p_date, 'null'), ')'));

	if 	not exists_commodity(p_guid) 
		or p_guid = get_default_currency_guid() -- no report for default currency
		or ifnull(p_unit_change,0) = 0 -- no report if no change in holding required
	then
		-- call log('DEBUG : get_signal A');
		return l_report;
	end if;

	-- set defaults and initialise
	set p_date = round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day) ));
	set l_days_back = if( ifnull( abs(get_variable('Days back') ),0 ) = 0, 1, abs(get_variable('Days back') ) );
	set l_date = round_timestamp( date_add( p_date, interval - l_days_back day) );
	if weekday(l_date) > 4 then -- if start date is a weekend (weekday = 5,6), go back to include previous friday
		set l_date = date_add(l_date, interval - (weekday(l_date) - 4) day);
	end if;	 
	set l_short_ema_days = ifnull(get_variable('Short EMA days'), 12);
	set l_long_ema_days = ifnull(get_variable('Long EMA days'), 26);
	set l_signal_days = ifnull(get_variable('Signal days'), 9);
	set l_gradient_sensitivity = ifnull(get_variable('Gradient sensitivity'), 0.01);

	-- create table to hold poll results
	drop temporary table if exists poll;
	create temporary table poll (
		metric			varchar(100),
		metric_date		timestamp,
		observation		varchar(100),
		vote			int, -- +ve vote = buy, -ve vote = sell
		primary key (metric)
	);

	repeat

		-- call log('DEBUG : get_signal NEW LOOP');

		-- [START] PPO analysis
		set l_vote = 0;
		set l_observation = null;

		call get_commodity_ppo(	
					p_guid, 
					l_date,
					l_ppo_line,
					l_ppo_signal_line,
					l_ppo_histogram
				);

		-- call log( concat('DEBUG : l_ppo_line=', ifnull(l_ppo_line, 'null')));
		-- call log( concat('DEBUG : l_ppo_signal_line=', ifnull(l_ppo_signal_line, 'null')));
		-- call log( concat('DEBUG : l_ppo_histogram=', ifnull(l_ppo_histogram, 'null')));	

		if 	l_previous_ppo_line is not null
			and l_previous_ppo_histogram is not null
		then

			set l_ppo_line_gradient = l_ppo_line - l_previous_ppo_line;
			set l_ppo_histogram_gradient = l_ppo_histogram - l_previous_ppo_histogram;

			-- V EARLY : divergences
			-- if l_ppo_histogram has been decreasing for 4 days
			-- and l_ppo_signal_line is -ve : BUY
			-- and l_ppo_signal_line is +ve : SELL

			if 	get_commodity_attribute(	p_guid,  
								concat('ppo_histogram(', l_short_ema_days, ',', l_long_ema_days,',', l_signal_days,')'), 
								date_add(l_date, interval - 3 day)
							)
				>
				get_commodity_attribute(	p_guid,  
								concat('ppo_histogram(', l_short_ema_days, ',', l_long_ema_days,',', l_signal_days,')'), 
								date_add(l_date, interval - 2 day)
							)
				>
				get_commodity_attribute(	p_guid,  
								concat('ppo_histogram(', l_short_ema_days, ',', l_long_ema_days,',', l_signal_days,')'), 
								date_add(l_date, interval - 1 day)
							)
				>
				get_commodity_attribute(	p_guid,  
								concat('ppo_histogram(', l_short_ema_days, ',', l_long_ema_days,',', l_signal_days,')'), 
								l_date
							)
			then

				if l_ppo_signal_line < 0 then
					set l_vote = 1;
					set l_observation = 'Very early buy';
				elseif l_ppo_signal_line > 0 then
					set l_vote = -1;
					set l_observation = 'Very early sell';	
				end if;

			end if;

			-- EARLY : ppo_line zero crossover
			-- ppo_line has crossed zero line

			-- try to avoid emitting crossover signals in a ranging market
			if 	l_ppo_line_gradient is not null
				and abs(l_ppo_line_gradient) >= l_gradient_sensitivity
				and (
					(	l_ppo_line > 0
						and l_previous_ppo_line	<= 0
					)
					or
					(
						l_ppo_line < 0
						and l_previous_ppo_line >= 0
					)
				)
			then

				if l_ppo_line_gradient > 0 then
					set l_vote = 2;
					set l_observation = 'Early buy';
				elseif l_ppo_line_gradient < 0 then
					set l_vote = -2;
					set l_observation = 'Early sell';	
				end if;

			end if;

			-- LATE : ppo_line signal line crossover
			-- ppo_line has crossed signal line

			-- try to avoid emitting crossover signals in a ranging market
			if 	l_ppo_histogram_gradient is not null
				and abs(l_ppo_histogram_gradient ) >= l_gradient_sensitivity
				and (
					(
						l_ppo_histogram > 0
						and l_previous_ppo_histogram <= 0	
					) 
					or 
					(
						l_ppo_histogram < 0
						and l_previous_ppo_histogram >= 0
					)
				)
			then

				if l_ppo_line_gradient > 0 then
					set l_vote = 3;
					set l_observation = 'Late buy';
				elseif l_ppo_line_gradient < 0 then
					set l_vote = -3;
					set l_observation = 'Late sell';	
				end if;
				
			end if;
		end if;

		-- call log( concat('DEBUG : [PPO] l_vote = ', ifnull(l_vote, 'null')));
		-- call log( concat('DEBUG : [PPO] l_observation = ', ifnull(l_observation, 'null')));

		if ifnull(l_vote,0) != 0 
		then
			replace into poll
				(metric, metric_date, observation, vote)
			values
				(
					'Percentage price oscillator', 
					l_date,
					l_observation,
					round(l_vote * ifnull(get_variable('Percentage price oscillator weighting'),1),0)
				);
		end if;

		-- remember values for next day
		set l_previous_ppo_line = l_ppo_line;
		set l_previous_ppo_histogram = l_ppo_histogram;

		-- [END] PPO analysis

		-- [START] SO analysis
		call get_commodity_so(	
					p_guid, 
					l_date,
					l_fast_so_line, 
					l_slow_so_line, 
					l_signal_line
				);

		-- call log( concat('DEBUG : l_fast_so_line=', ifnull(l_fast_so_line, 'null')));
		-- call log( concat('DEBUG : l_slow_so_line=', ifnull(l_slow_so_line, 'null')));
		-- call log( concat('DEBUG : l_signal_line=', ifnull(l_signal_line, 'null')));

		-- (long term) oversold / overbought indicator
		set l_vote = 0;
		set l_observation = null;
		case
			when l_slow_so_line < 10 then set l_vote = 3; set l_observation = 'Very oversold';
			when l_slow_so_line < 20 then set l_vote = 2; set l_observation = 'Oversold';
			when l_slow_so_line < 30 then set l_vote = 1; set l_observation = 'Mildly oversold';
			when l_slow_so_line > 90 then set l_vote = -3; set l_observation = 'Very overbought';
			when l_slow_so_line > 80 then set l_vote = -2; set l_observation = 'Overbought';
			when l_slow_so_line > 70 then set l_vote = -1; set l_observation = 'Mildly overbought';
			else set l_vote = 0;	
		end case;

		-- call log( concat('DEBUG : [LTSO] l_vote = ', ifnull(l_vote, 'null')));
		-- call log( concat('DEBUG : [LTSO] l_observation = ', ifnull(l_observation, 'null')));

		if ifnull(l_vote,0) != 0
		then
			replace into poll
				(metric, metric_date, observation, vote)
			values
				(
					'Long term stochastic oscillator', 
					l_date,
					l_observation,
					round(l_vote * ifnull(get_variable('Long term stochastic oscillator weighting'),1),0)
				);
		end if;

		-- (short term) oversold / overbought indicator
		set l_vote = 0;
		set l_observation = null;
		case
			when l_fast_so_line < 10 then set l_vote = 3; set l_observation = 'Very oversold';
			when l_fast_so_line < 20 then set l_vote = 2; set l_observation = 'Oversold';
			when l_fast_so_line < 30 then set l_vote = 1; set l_observation = 'Mildly oversold';
			when l_fast_so_line > 90 then set l_vote = -3; set l_observation = 'Very overbought';
			when l_fast_so_line > 80 then set l_vote = -2; set l_observation = 'Overbought';
			when l_fast_so_line > 70 then set l_vote = -1; set l_observation = 'Mildly overbought';
			else set l_vote = 0;	
		end case;

		-- call log( concat('DEBUG : [STSO] l_vote = ', ifnull(l_vote, 'null')));
		-- call log( concat('DEBUG : [STSO] l_observation = ', ifnull(l_observation, 'null')));

		if ifnull(l_vote,0) != 0 
		then
			replace into poll
				(metric, metric_date, observation, vote)
			values
				(
					'Short term stochastic oscillator', 
					l_date,
					l_observation,
					round(l_vote * ifnull(get_variable('Short term stochastic oscillator weighting'),1),0)
				);
		end if;

		-- bull/bear divergences
		-- todo

		-- bull/bear setups
		-- todo

		-- [END] SO analysis

		-- next day
		set l_date = date_add(l_date, interval 1 day);

	until l_date > p_date
	end repeat;

	-- [START] Extremes analysis
	set l_vote = 0;
	set l_observation = null;

	set l_days_since_high = datediff(p_date, get_commodity_extreme_date(p_guid, 'HIGH', p_date));
	set l_days_since_low = datediff(p_date, get_commodity_extreme_date(p_guid, 'LOW', p_date));

	-- call log( concat('DEBUG : l_days_since_high=', ifnull(l_days_since_high, 'null')));
	-- call log( concat('DEBUG : l_days_since_low=', ifnull(l_days_since_low, 'null')));

	-- ignore differences within 'Ignore extremes' days
	-- effectively, one vote is given for each quarter (3 months), capped to 5 votes (ie 1.25 years) to avoid overwhelming other signals
	if ifnull(l_days_since_high,0) > ifnull(get_variable('Ignore extremes'),7) then
		set l_vote = - l_days_since_high / 91; -- -ve because this is a sell signal

		-- cap vote
		if l_vote < - ifnull(get_variable('Vote cap'),5) then
			set l_vote = - ifnull(get_variable('Vote cap'),5);
		end if;
			
		if 	l_days_since_high <= 13 then
			set l_observation = concat( pluralise( round(l_days_since_high,0), 'day' ), ' since price was this high');
		elseif 	l_days_since_high <= 55 then
			set l_observation = concat( pluralise( round(l_days_since_high / 7,0), 'week' ), ' since price was this high');
		elseif l_days_since_high <= 364 then
			set l_observation = concat( pluralise( round(l_days_since_high / 31,0), 'month'), ' since price was this high');
		else
			set l_observation = concat( pluralise( round(l_days_since_high / 365.25, 1), 'year'), ' since price was this high');
		end if;

		if ifnull(l_vote,0) != 0 
		then
			replace into poll
				(metric, metric_date, observation, vote)
			values
				(
					'Extreme high', 
					p_date,
					l_observation,
					round(l_vote * ifnull(get_variable('Extremes weighting'),1),0)
				);
		end if;
	end if;

	if ifnull(l_days_since_low,0) > ifnull(get_variable('Ignore extremes'),7) then
		set l_vote = l_days_since_low / 91;

		if l_vote > ifnull(get_variable('Vote cap'),5) then
			set l_vote = ifnull(get_variable('Vote cap'),5);
		end if;
			
		if 	l_days_since_low <= 13 then
			set l_observation = concat( pluralise( round(l_days_since_low,0) , 'day' ), ' since price was this low');
		elseif 	l_days_since_low <= 55 then
			set l_observation = concat( pluralise( round(l_days_since_low / 7,0), 'week' ), ' since price was this low');
		elseif l_days_since_low <= 364 then
			set l_observation = concat( pluralise( round(l_days_since_low / 31,0), 'month'), ' since price was this low');
		else
			set l_observation = concat( pluralise( round(l_days_since_low / 365.25, 1), 'year'), ' since price was this low');
		end if;

		-- call log( concat('DEBUG : [extremes] l_vote = ', ifnull(l_vote, 'null')));
		-- call log( concat('DEBUG : [extremes] l_observation = ', ifnull(l_observation, 'null')));

		if ifnull(l_vote,0) != 0 
		then
			replace into poll
				(metric, metric_date, observation, vote)
			values
				(
					'Extreme low', 
					p_date,
					l_observation,
					round(l_vote * ifnull(get_variable('Extremes weighting'),1),0)
				);
		end if;
	end if;

	-- [END] Extremes analysis

	-- Calculate BUY/SELL conclusion with more weight given to later signals; majority wins
	-- full weight is given to signals from today and the previous work day (which might be yesterday or Friday)
	select 	sum( vote / 	if( 	datediff(p_date, metric_date) <= 1
					or weekday(p_date) = 0 and datediff(p_date, metric_date) <= 3, 
					1, 
					(datediff(p_date, metric_date)/2) -- /2 to make tail-off slightly less aggressive 
				) 
		)
	into 	l_vote
	from 	poll;

	-- call log( concat('DEBUG : l_vote = ', ifnull(l_vote, 'null')));

	-- dynamically set strong/mild/weak boundaries
	set l_max_vote = 	3 * ifnull(get_variable('Percentage price oscillator weighting'),1) + 
				3 * ifnull(get_variable('Short term stochastic oscillator weighting'),1) +
				ifnull(get_variable('Vote cap'),5) * ifnull(get_variable('Extremes weighting'),1);

	set l_strong_vote = (2 * l_max_vote)/3;
	set l_mild_vote = l_max_vote/3;

	-- log a warning if the weak vote filter is set too high
	if ifnull(get_variable('Filter weak signals'), '1') > l_max_vote
	then
		call log( concat('WARNING : Variable ''Filter weak signals'' may be set too high. Recommended setting : ', round(l_mild_vote,0) ));	
	end if;

	-- filter out weak signals if requested
	if 	abs(l_vote) > ifnull(get_variable('Filter weak signals'), '1') 
	then

		-- convert votes to text
		if abs(l_vote) > l_max_vote then
			set l_conclusion = 'VERY STRONG';
		elseif abs(l_vote) > l_strong_vote then
			set l_conclusion = 'STRONG';
		elseif abs(l_vote) > l_mild_vote then
			set l_conclusion = 'MILD';
		else
			set l_conclusion = 'WEAK';
		end if;

		if p_unit_change < 0 and p_predicted_gain >= 0 and l_vote < 0 then
			set l_conclusion = concat('<font color=blue><b>', l_conclusion, ' SELL</b></font>');
		elseif p_unit_change > 0 and l_vote > 0 then
			set l_conclusion = concat('<font color=green><b>', l_conclusion, ' BUY</b></font>');
		else
			set l_conclusion = null;
		end if;

		-- call log( concat('DEBUG : l_conclusion = ', ifnull(l_conclusion, 'null')));

		-- add explanation if required
		if l_conclusion is not null and get_variable('Explain') = 'Verbose' then

			report_block : begin
				declare l_poll_line		text;
				declare l_poll_done_temp 	boolean default false;
				declare l_poll_done		boolean default false;

				declare lc_poll cursor for
					select distinct
						concat (date_format(metric_date, '%d %b'), '|',
							metric, '|',
							observation
						)
					from poll
					order by metric_date desc, metric;
				declare continue handler for not found set l_poll_done =  true;

				open lc_poll;
				set l_poll_done = false;

				poll_loop : loop
					fetch lc_poll into l_poll_line;

					if l_poll_done then 
						leave poll_loop;
					else
						set l_poll_done_temp = l_poll_done;
					end if;

					call write_report(	l_verbose_report,
					 			l_poll_line,
					 			'table-middle');

					set l_poll_done = l_poll_done_temp;
													
				end loop; -- poll_loop

				close lc_poll;

			end; -- report_block
				
			call write_report(	l_verbose_report,
			 			'Date|Metric|Observation',
			 			'table-start');

			call write_report(	l_verbose_report,
			 			null,
						'table-end');

			call write_report(	l_report,
						l_conclusion,
						'plain');

			call write_report(	l_report,
						l_verbose_report,
						'plain');

		else
			set l_report = l_conclusion;

		end if;
	end if;

	-- call log('DEBUG : END get_signal');

	return l_report;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] Adds a new commodity price to the commodity price table
-- if its sane, and hasn't already been added
-- designed to be called from an OS scheduler using gnc-fq-dump to obtain quotes :
drop function if exists post_commodity_price;
//
create function post_commodity_price
	(
		p_commodity		varchar(32),
		p_date			timestamp,
		p_currency		varchar(32),
		p_value			decimal(20,6),
		p_source		varchar(2048)
	)
	returns varchar(32)
begin
	declare l_previous_price 	decimal(20,6);
	declare l_26_day_sma	 	decimal(20,6) default null;
	declare l_previous_date		timestamp;
	declare l_previous_denom 	bigint(20);
	declare l_previous_currency 	varchar(32);
	declare l_guid 			varchar(32);

	-- call log( concat('DEBUG : START post_commodity_price(', ifnull(p_commodity, 'null'), ',', ifnull(p_date, 'null'), ',', ifnull(p_currency, 'null'), ',', ifnull(p_value, 'null'), ',', ifnull(p_source, 'null'), ')'));

	-- try to play nicely with other procedures
	do is_locked('prices', 'WAIT');

	-- convert to guid
	if not is_guid(p_commodity) then
		set p_commodity = get_commodity_guid(p_commodity);
	end if;

	if not is_guid(p_currency) then
		set p_currency = get_commodity_guid(p_currency);
	end if;

	set p_commodity = trim(p_commodity);
	
	if 	p_commodity is not null
		and p_currency is not null
		and p_date is not null
		and date_format(p_date, '%Y') != '0000'
		and exists_commodity(p_commodity) 
		and is_currency(p_currency)
		and is_number(p_value)
		and p_date <= current_date
		and p_date >= date_add(current_date, interval - get_variable('Maximum quote age') year)
	then
		-- set defaults
		set l_previous_date 	= date_add(p_date, interval - 1 day);
		set l_previous_price 	= get_commodity_price( p_commodity, l_previous_date);
		set l_previous_denom 	= get_commodity_latest_denom( p_commodity );
		set l_previous_currency = get_commodity_currency( p_commodity );
		set l_26_day_sma 	= get_commodity_sma(p_commodity, 26, l_previous_date);

		-- gnc-fq-dump (or yahoo) has the occasional tendency to report GBP/GBp prices a factor of 100 out
		-- (it can also lie about the currency the quote is in)
		if 	l_26_day_sma is not null
			and abs(p_value - l_26_day_sma) / l_26_day_sma >= 0.95 
		then
			if p_value > l_26_day_sma then
				set p_value = p_value / 100;
			else
				set p_value = p_value * 100;
			end if;

		-- SMA is a better metric, but if that can't be calculated, use the previous price (if any) instead
		elseif	l_previous_price is not null
			and abs(p_value - l_previous_price) / l_previous_price >= 0.95 
		then
			if p_value > l_previous_price then
				set p_value = p_value / 100;
			else
				set p_value = p_value * 100;
			end if;
		end if;

		-- insert price values if they appear sane
		case

			-- minor faults (which actually occur too often to be bothered about)
			when 	exists_price(p_commodity, p_date) 
			then
				-- call log( concat('WARNING : New price ' , get_commodity_mnemonic(p_currency) , ' ',  convert(p_value, char) , ' for ',  if( is_currency( p_commodity ) , 'currency ', 'commodity ') , get_commodity_mnemonic(p_commodity), ' not inserted because a price already exists for ', date_format(p_date, '%Y-%m-%d'), '.' ));
				begin
					-- deliberately empty statement (ie, do nothing)
				end;
			when 	l_previous_price is not null
				and p_value = l_previous_price 
			then
				-- call log( concat('WARNING : New price ' , get_commodity_mnemonic(p_currency) , ' ',  convert(p_value, char) , ' for ',  if( is_currency( p_commodity ) , 'currency ', 'commodity ') , get_commodity_mnemonic(p_commodity), ' for ',  date_format(p_date, '%Y-%m-%d'), ' not inserted because the new value is the same as the previous one.' ));
				begin
					-- deliberately empty statement (ie, do nothing)
				end;
			
			-- major faults
			when 	l_previous_currency != p_currency
			then
				call log( concat('WARNING : New price ' , get_commodity_mnemonic(p_currency) , ' ',  convert(p_value, char) , ' for ',  if( is_currency( p_commodity ) , 'currency ', 'commodity ') , get_commodity_mnemonic(p_commodity), ' for ',  date_format(p_date, '%Y-%m-%d'), ' not inserted because the currencies dont match.' ));		

			when 	l_26_day_sma is not null
				and abs(p_value - l_26_day_sma) / l_26_day_sma > (get_variable('New quote filter')/100) 
			then
				call log( concat('WARNING : New price ' , get_commodity_mnemonic(p_currency) , ' ',  convert(p_value, char) , ' for ',  if( is_currency( p_commodity ) , 'currency ', 'commodity ') , get_commodity_mnemonic(p_commodity), ' for ',  date_format(p_date, '%Y-%m-%d'), ' not inserted because the new value is >', get_variable('New quote filter'), '% different from the 26 day SMA (', l_26_day_sma, ').'  ));

			when 	l_26_day_sma is null
				and l_previous_price is not null
				and abs(p_value - l_previous_price) / l_previous_price > (get_variable('New quote filter')/100) 
			then
				call log( concat('WARNING : New price ' , get_commodity_mnemonic(p_currency) , ' ',  convert(p_value, char) , ' for ',  if( is_currency( p_commodity ) , 'currency ', 'commodity ') , get_commodity_mnemonic(p_commodity), ' for ',  date_format(p_date, '%Y-%m-%d'), ' not inserted because the new value is >', get_variable('New quote filter'), '% different from the previous price (', l_previous_price, ').'  ));

			else

				if gnc_lock('prices') then

					set l_guid = new_guid();

					insert into prices (
						guid, 
						commodity_guid, 
						currency_guid, 
						date, 
						source,
						type, 
						value_num, 
						value_denom
					)
					values (
						l_guid,
						p_commodity,
						ifnull(get_commodity_currency(p_commodity), p_currency),
						p_date,
						ifnull(p_source, 'Finance::Quote'),
						'last',
						p_value * ifnull(l_previous_denom, 1000000),	-- quotes for previously unquoted commodities have no denom, so assume max for decimal(20,6) type
						ifnull(l_previous_denom, 1000000)		
					);

					call gnc_unlock('prices');

					-- log action
					call log( concat('INFORMATION : Inserted new price ' , 
							ifnull(get_commodity_mnemonic(p_currency), 'NULL') , ' ',  
							ifnull(convert(p_value, char), 'NULL') , ' for ',  
							if( is_currency( p_commodity ) , 'currency ', 'commodity ') , 
							ifnull(get_commodity_mnemonic(p_commodity), 'NULL'), ' for ',  
							ifnull(date_format(p_date, '%Y-%m-%d'), 'NULL'), '.' 
						));			

				end if;

		end case;
	else
		call log( concat('WARNING : New price ' , 
				ifnull(get_commodity_mnemonic(p_currency), 'NULL') , ' ',  
				ifnull(convert(p_value, char), 'NULL') , ' for ',  
				if( is_currency( p_commodity ), 'currency ', 'commodity ') , 
				ifnull(get_commodity_mnemonic(p_commodity), 'NULL'), ' for ',  
				ifnull(date_format(p_date, '%Y-%m-%d'), 'NULL'), ' is not valid.'
			));

	end if;

	-- call log('DEBUG : END post_commodity_price');

	return l_guid;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] Cleans up prices table, which may contain duplicates or missing values
drop procedure if exists clean_prices;
//
create procedure clean_prices
	(
		p_guid		varchar(32) -- optionally limit effect to one commodity
	)
procedure_block : begin
	declare l_guid				varchar(32);
	declare l_commodity_guid		varchar(32);
	-- declare l_previous_commodity_guid	varchar(32);
	declare l_currency_guid			varchar(32);
	declare l_date				timestamp;
	-- declare l_previous_date		timestamp;
	declare l_value				decimal(20,6);
	-- declare l_30_day_sma			decimal(20,6);
	-- declare l_field			varchar(100);
	declare l_source			varchar(2048);
	declare l_type				varchar(2048);
	declare	l_count_before 			integer default 0;
	declare l_count_after			integer default 0;
	declare l_duplicate_price_done 		boolean default false;
	declare l_duplicate_price_done_temp 	boolean default false;
	declare l_missing_price_done 		boolean default false;
	declare l_missing_price_done_temp 	boolean default false;
	-- declare l_earliest_date		timestamp default current_timestamp;

	-- declare l_x_100_done 		boolean default false;
	-- declare l_x_100_done_temp 		boolean default false;
	-- declare l_report			text;
	-- declare l_report_header		varchar(500);

	-- call log('DEBUG : START clean_prices');

	-- try to play nicely with other procedures
	do is_locked('prices, commodity_attribute', 'WAIT');

	-- if a commodity is specified, convert to a guid
	if 	p_guid is not null 
		and not is_guid(p_guid) 
	then
		set p_guid = get_commodity_guid(p_guid);
	end if;

	-- delete prices with malformed dates (which could only appear if there's been a bug elsewhere - but it has happened!)
	delete from prices
	where 	date_format(prices.date, '%Y') = '0000'
		and (p_guid is null or p_guid = prices.commodity_guid); 

	delete from commodity_attribute
	where 	date_format(commodity_attribute.value_date, '%Y') = '0000'
		and commodity_attribute.field in ('last', 'price')
		and (p_guid is null or p_guid = commodity_attribute.commodity_guid); 

	-- add prices that are in commodity_attributes but missing from prices (within the last get_variable('Price check') days)
	missing_prices : begin
		declare lc_missing_price cursor for
			select distinct 
				commodity_attribute.commodity_guid,
				round_timestamp(commodity_attribute.value_date),
				trim(commodity_attribute.value)
				-- commodity_attribute.field
			from	commodity_attribute
			where 	-- the value is a price
				commodity_attribute.field in ('last', 'price')
				-- the value is a number
				and is_number(commodity_attribute.value)
				-- the values date is between get_variable('Price check') days ago and now
				and commodity_attribute.value_date <= current_date
				and commodity_attribute.value_date >= date_add(current_date, interval - ifnull(get_variable('Price check'),30) day)
				-- the value is not the same as the previous days
				and commodity_attribute.value != get_commodity_price( commodity_attribute.commodity_guid, date_add(commodity_attribute.value_date, interval - 1 day))
				-- a value has not already been entered for that day
				and not exists_price(commodity_attribute.commodity_guid, commodity_attribute.value_date)
				-- and commodity_attribute.value != get_commodity_price(commodity_attribute.commodity_guid, commodity_attribute.value_date)
				and (p_guid is null or p_guid = commodity_attribute.commodity_guid)
			order by 
				commodity_attribute.commodity_guid,
				commodity_attribute.value_date asc;
		declare continue handler for not found set l_missing_price_done =  true;

		-- work through missing prices
		open lc_missing_price;	
		set l_missing_price_done = false;
		
		missing_price_loop : loop
	
			fetch lc_missing_price 
			into l_commodity_guid, l_date, l_value;
		
			if l_missing_price_done then 
				leave missing_price_loop;
			else
				set l_missing_price_done_temp = l_missing_price_done;
			end if;	

			do post_commodity_price(	
					l_commodity_guid,
					l_date,
					if( 	is_currency(l_commodity_guid),
						get_default_currency_guid(),
						get_commodity_guid( get_commodity_attribute(l_commodity_guid, 'currency', l_date) )
					),
					l_value,
					ifnull(get_commodity_attribute(l_commodity_guid, 'method', l_date), 'Finance::Quote')
				);

			-- nix any dependent attributes
			if not is_locked('commodity_attribute', 'WAIT') then
				call delete_derived_commodity_attributes(l_commodity_guid, l_date);
			end if;

			set l_count_after = l_count_after + 1;
			set l_missing_price_done = l_missing_price_done_temp;

		end loop;

		close lc_missing_price;	

		-- log work done
		if l_count_after > 0 then
			call log(concat('INFORMATION : attempted to add ', l_count_after, ' missing records to the prices table.'));
		end if;

	end; -- missing_prices : begin

	-- remove duplicates
	duplicate_prices : begin
		declare lc_duplicate_price cursor for
			select distinct
				commodity_guid,
				currency_guid,
				round_timestamp(date),
				round(value_num/value_denom,6),
				max(source),
				max(type)
			from 	prices
			where 	(p_guid is null or p_guid = commodity_guid)
			group by
				commodity_guid,
				currency_guid,
				round_timestamp(date),
				round(value_num/value_denom,6)
			having count(*) >1;
		declare continue handler for not found set l_duplicate_price_done =  true;

		-- count prices in DB before change
		select 	count(*)
		into 	l_count_before
		from 	prices;
	
		-- work through duplicates
		open lc_duplicate_price;	
		set l_duplicate_price_done = false;
	
		duplicate_price_loop : loop
		
			fetch lc_duplicate_price 
			into l_commodity_guid, l_currency_guid, l_date, l_value, l_source, l_type;
	
			if l_duplicate_price_done then 
				leave duplicate_price_loop;
			else
				set l_duplicate_price_done_temp = l_duplicate_price_done;
			end if;

			if gnc_lock('prices') then

				-- delete *all* matching values
				delete from prices
				where
					commodity_guid = l_commodity_guid
					and currency_guid = l_currency_guid
					and round_timestamp(date) = l_date
					and round(value_num/value_denom,6) = l_value;

				-- re-insert *one* matching value
				insert into prices (
					guid, 
					commodity_guid, 
					currency_guid, 
					date, 
					source,
					type, 
					value_num, 
					value_denom
				)
				values (
					new_guid(),
					l_commodity_guid,
					l_currency_guid,
						l_date,
						l_source,
						l_type,
						l_value * 1000000,
						1000000
					);

				call gnc_unlock('prices');
			end if;		

			set l_duplicate_price_done = l_duplicate_price_done_temp;

		end loop;

		close lc_duplicate_price;	

		-- count prices in DB before change
		select count(*)
		into l_count_after
		from prices;

		-- log work done
		if l_count_before - l_count_after > 0 then
			call log(concat('INFORMATION : attempted to remove ', l_count_before - l_count_after, ' duplicate records from the prices table.'));
		end if;

	end; -- duplicate_prices : begin

/*
	-- report any x/100 or x*100 issues occasionally observed through Finance::Quote or Yahoo Finance
	x_100 : begin
		-- identify candidates for update
		declare lc_x_100 cursor for
			select distinct
				prices.guid,
				prices.commodity_guid,
				prices.date,
				round(prices.value_num/prices.value_denom,6),
				get_commodity_sma(prices.commodity_guid, 30, date_add(prices.date, interval -1 day))
			from	prices
			where	prices.value_num > 0
			and	prices.commodity_guid != get_default_currency_guid()
			and 	abs( get_commodity_sma(prices.commodity_guid, 30, date_add(prices.date, interval -1 day)) - prices.value_num/prices.value_denom ) 
				/ 
				get_commodity_sma(prices.commodity_guid, 30, date_add(prices.date, interval -1 day)) 
				>= 0.95
			and 	(p_guid is null or p_guid = prices.commodity_guid)
			order by 
				prices.commodity_guid,
				prices.date asc;
		declare continue handler for not found set l_x_100_done =  true;

		if	get_variable ('Report') != 'Y'
		then
			call log(concat('WARNING : Report declined to start; Gnucash status = ' , get_variable('Gnucash status') , 'Reporting = ' , get_variable ('Report') ));
			leave x_100;
		end if;
		
		-- this is v difficult; Yahoo finance reports prices x/100, x*100 or in a different currency within one CSV, or lies about the currency through gnc_fq_quote, 
		-- so a lot of price data is uncorrectable garbage

		open lc_x_100;	
		set l_x_100_done = false;
		set l_count_after = 0;
	
		x_100_loop : loop
		
			fetch lc_x_100 
			into l_guid, l_commodity_guid, l_date, l_value, l_30_day_sma;
	
			if l_x_100_done 
			then 
				leave x_100_loop;
			else
				set l_x_100_done_temp = l_x_100_done;
			end if;

			-- report on candidate error (do not fix it automatically)
			call write_report(	l_report,
						concat(
							'Commodity "', get_commodity_mnemonic(l_commodity_guid), 
							'", date "', date_format(l_date, "%Y-%m-%d"), 
							'", recorded price "', l_value, 
							'", perhaps should be "', 
							convert( 
								round(
									if(	l_value > l_30_day_sma,
										l_value / 100,
										l_value * 100
									)
								, 0), 
							char),
							'"|',
							'update prices </br>set value_denom = 1000000, value_num = ',
							convert( 
								round(	
									if(	l_value > l_30_day_sma,
										l_value * 1000000 / 100,
										l_value * 1000000 * 100
									)
								, 0), 
							char),
							'</br> where commodity_guid = ''', l_commodity_guid, ''';',
							'</br>', 
							'call delete_derived_commodity_attributes(''', l_commodity_guid, 
							''', str_to_date(''', date_format(date_add(l_date, interval -1 day), "%Y-%m-%d"), ''',''%Y-%m-%d'');'
						),
						'table-middle'
					);


			-- fix the problem
			-- set l_30_day_sma = get_commodity_sma(l_commodity_guid, 30, date_add(l_date, interval -1 day));
			-- if abs( l_30_day_sma - l_value ) /  l_30_day_sma >= 0.95 then

			--	update 	prices
			--	set	value_denom	= 1000000
			--		value_num	= if(	l_value > l_30_day_sma,
			--					l_value * 1000000 / 100,
			--					l_value * 1000000 * 100
			--					)
			--	where 	commodity_guid = l_guid;

				-- nix any dependent attributes
				-- note that this potentially causes the sma(30) value used in the select cursor to be recalculated in the update command
			--	call delete_derived_commodity_attributes(l_commodity_guid, date_add(l_date, interval -1 day));

			--end if;

			
			set l_x_100_done = l_x_100_done_temp;
			-- set l_count_after = l_count_after + 1;

		end loop;

		close lc_x_100;

		if l_report is not null then

			-- create table header
			call write_report(	l_report_header,
						'Error|Fix',
						'table-start');
	

			-- stick header on in correct place
			set l_report = concat(l_report_header, l_report);

			-- complete report
			call write_report(	l_report,
						null,
						'table-end');

			-- stick on subject line
			call write_report(	l_report, 
						'Price anomaly report', 
						'title');

			-- delete previous iterations of report (only the latest is relevant)
			call delete_series('report_price_anomaly', null);

			-- write completed report to variables table
			call post_variable('report_price_anomaly' , l_report);

		end if;

		-- log work done
		-- if l_count_before - l_count_after > 0 then
		--	call log(concat('INFORMATION : ', l_count_after, ' records displaying x/100 errors fixed in the prices table.'));
		-- end if;

	end; -- x_100 : begin
*/
/*
	OLD -- fix the x/100 issue occasionally observed through Finance::Quote or Yahoo Finance
	-- this is automatically fixed for newly added quotes, but may get through for bulk loading of historical quotes
	select 	count(*)
	into	l_count_after
	from	prices
	where	prices.value_num > 0
	and	prices.commodity_guid != get_default_currency_guid()
	and 	( get_commodity_sma(prices.commodity_guid, 30, prices.date) - prices.value_num/prices.value_denom ) 
		/ 
		get_commodity_sma(prices.commodity_guid, 30, prices.date) 
			>= 0.95;

	if ifnull(l_count_after, 0) > 0
	then
		-- clean up dependent attributes
		update	prices
		set	prices.value_num = prices.value_num * 100
		where	prices.value_num > 0
		and	prices.commodity_guid != get_default_currency_guid()
		and 	( get_commodity_sma(prices.commodity_guid, 30, prices.date) - prices.value_num/prices.value_denom ) 
			/ 
			get_commodity_sma(prices.commodity_guid, 30, prices.date)
				>= 0.95; 

		-- clean up dependent attributes (how??)
		-- delete from	commodity_attributes
		-- where		commodity_guid = l_commodity_guid
		-- and		value_date >= l_date
		-- and		(field like 'sma%' field like 'ema%' or field like 'so%' or field like 'ppo%' or field like 'macd%');

		call log(concat('INFORMATION : ',  l_count_after, ' price records corrected in the prices table.'));
	end if;
*/
	-- call log('DEBUG : END clean_prices');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [RW] Cleans up commodities table; removes quote flag for out-of-date commodities
drop procedure if exists clean_commodities;
//
create procedure clean_commodities()
procedure_block : begin

	declare l_commodities			varchar(100);
	declare l_currency			varchar(100);

	-- call log('DEBUG : START clean_commodities');

	-- check if default currency is still sensible
	select 	get_commodity_mnemonic(default_currency.commodity_guid)
	into 	l_currency
	from ( 
		select commodity_guid, count(*) 
		from accounts 
		where is_currency(commodity_guid) 
		group by commodity_guid 
		order by 2 desc limit 1 
	) default_currency;
		
	if l_currency != get_constant('Default currency') then
		call log( concat('WARNING : your most used currency is "', l_currency, '" not the default currency "', get_constant('Default currency'), '". To change it, run (in MySQL) : call put_variable(''Default currency'',''', l_currency,''');'));
	end if;

	if get_variable('Gnucash status') = 'RW' then

		-- turn off quoting for commodities where a value has not been received for 'Stop quoting' (default 6) months
		select 	group_concat( distinct commodities.mnemonic )
		into	l_commodities
		from 	commodities
		where 	commodities.quote_flag = 1
		and 	commodities.mnemonic != get_constant('Default currency')
	   	and 	datediff(current_date, get_commodity_latest_date(commodities.guid)) > ifnull(get_variable('Stop quoting'), 6) * 30;

		if l_commodities is not null and gnc_lock('commodities') then

			update 	commodities
			set 	quote_flag = 0
			where 	commodities.quote_flag = 1
			and 	commodities.mnemonic != get_constant('Default currency')
		   	and 	datediff(current_date, get_commodity_latest_date(commodities.guid)) > ifnull(get_variable('Stop quoting'), 6) * 30;

			call gnc_unlock('commodities');

			call log( concat('WARNING : turned off quoting for commodities "', l_commodities, '" because no value has been received in ', ifnull(get_variable('Stop quoting'), 6), ' months'));

		end if;

		set l_commodities = null;

		-- count how many commodities have been quoted in the last week
		select 	group_concat( distinct commodities.mnemonic )
		into	l_commodities
		from	commodities
		where 	commodities.quote_flag = 1
		and 	commodities.mnemonic != get_constant('Default currency')
           	and 	datediff(current_date, get_commodity_latest_date(commodities.guid)) > 7
		and	datediff(current_date, get_variable_date('Gnucash status')) > 7;

		if l_commodities is not null then
			call log( concat('WARNING : quotes for commodities "', l_commodities, '" have not been updated in the last week.'));
		end if; 

	end if; -- if get_variable('Gnucash status') = 'RW'

	-- call log('DEBUG : END clean_commodities');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [E] TRANSACTION AND SPLIT ROUTINES

-- [R] returns true if there is already a relationship between two specified accounts in a split
-- this is irrespective of the 'direction' of the transaction
drop function if exists exists_split;
//
create function exists_split
	(
		p_transaction_guid	varchar(32),
		p_account1		varchar(32),
		p_account2		varchar(32)
	)
	returns 			boolean
begin
	declare l_count 		int;

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');
	
	select 		count(transactions.guid)
	into 		l_count
	from		
			transactions transactions
		join 	splits splits1
			on	transactions.guid = splits1.tx_guid
		join 	splits splits2
			on	transactions.guid = splits2.tx_guid
	where 
			transactions.guid = p_transaction_guid
			and (
					(splits1.account_guid = p_account1
					and 
					splits2.account_guid = p_account2 )
				or
					(splits1.account_guid = p_account2
					and 
					splits2.account_guid = p_account1 )
			);

	if l_count = 0 then
		return false;
	else
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if there is already a relationship between two specified accounts in any transaction between two dates
-- this is irrespective of the 'direction' of the transaction
drop function if exists exists_transaction;
//
create function exists_transaction
	(
		p_account1		varchar(32),
		p_account2		varchar(32),
		p_date1			timestamp,
		p_date2			timestamp
	)
	returns 			boolean
begin
	declare l_count 		int;
	declare l_date			timestamp;

	-- check for sane input
	if	not exists_account(p_account1)
		or not exists_account(p_account2)
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	-- use earliest and latest transaction dates if none provided
	if p_date2 is null then

		select 	max(post_date)
		into 	p_date2
		from 	transactions
			join splits 
				on transactions.guid = splits.tx_guid
		where 	splits.account_guid in ( p_account1, p_account2);
		-- and 	post_date <= current_timestamp;

	end if;

	if p_date1 is null then

		select 	min(post_date)
		into 	p_date1
		from 	transactions
			join splits 
				on transactions.guid = splits.tx_guid
		where 	splits.account_guid in ( p_account1, p_account2)
		and 	post_date <= p_date2;

	end if;

	-- make sure dates are in the right order
	if p_date1 > p_date2
	then
		set l_date = p_date1;
		set p_date1 = p_date2;
		set p_date2 = l_date;
	end if;

	select		count(transactions.guid)
	into		l_count
	from		transactions transactions
		join 	splits splits1
			on	transactions.guid = splits1.tx_guid
		join 	splits splits2
			on	transactions.guid = splits2.tx_guid
	where 				
			splits1.value_num + splits2.value_num = 0
		and 	splits1.account_guid = p_account1
		and 	splits2.account_guid = p_account2
		and 	transactions.post_date >= p_date1
		and	transactions.post_date <= p_date2;

	if l_count = 0 then
		return false;
	else
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns a CSV list of guid or accounts involved in a given transaction
drop function if exists get_transaction_accounts;
//
create function get_transaction_accounts
	(
		p_guid	varchar(32)
	)
	returns text -- varchar(60000)
begin
	declare l_accounts	text; -- varchar(60000);

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	select 	group_concat(distinct splits.account_guid)
	into 	l_accounts
	from 	transactions
		join splits on transactions.guid = splits.tx_guid
	where 	transactions.guid = p_guid 
	limit 	1;

	return l_accounts;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] totals up specified transactions between accounts between two dates 
-- and returns value in specified currency
-- note that if p_guid2 is a holding account and p_recursive is true, this operation can take a VERY long time to complete
drop function if exists get_transactions_value;
//
create function get_transactions_value
	(
		p_guid1			varchar(32), -- account guid (always specific; children are never counted)
		p_guid2			varchar(32), -- account guid (may include children if p_recursive=true)
		p_currency		varchar(32),
		p_date1			timestamp,
		p_date2			timestamp,
		p_recursive		boolean
	)
	returns 			decimal(20,6)
begin
	declare l_date 			timestamp;
	declare l_value 		decimal(20,6) default 0;

 	-- call log( concat(	'DEBUG : START get_transactions_value(', 
	--			ifnull(p_guid1, 'null'), ',', 
	--			ifnull(p_guid2, 'null'), ',', 
	--			ifnull(p_currency, 'null'), ',', 
	--			ifnull(p_date1, 'null'), ',', 
	--			ifnull(p_date2, 'null'), ',', 
	--			ifnull(p_recursive, 'null'), ')'
	--	));

	-- short circuit
	-- if not exists_transaction(p_guid1, p_guid2, null, null) then
	-- 	return 0;
	-- end if;

	-- set default currency
	set p_currency = ifnull( p_currency, get_default_currency_guid() );

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	-- set default date
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions;
	end if;
	-- set p_date2 = ifnull(p_date2, current_timestamp);

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = ifnull(p_date2, current_timestamp);
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- get list of p_guid2 subaccounts, if requested
	-- if ifnull(p_recursive, false) then
		-- mysql appears to have implementation limits that result in p_guid2 only containing 1024 chars
	--	call put_element(p_guid2 , get_account_children( p_guid2, true), ',');
	-- end if;

	-- call log( concat('DEBUG : get_account_children( p_guid2, true)=', get_account_children( p_guid2, true)));
	-- call log( concat('DEBUG : p_guid2=', p_guid2));

	select
			sum( transaction_set.value)
	into		l_value
	from
	(
		select	convert_value(
					- splits2.value_num/splits2.value_denom,
					transactions2.currency_guid,
					p_currency,
					transactions2.post_date
				) as value
		from
				splits splits2
			join	transactions transactions2
				on	transactions2.guid = splits2.tx_guid	
		where		
			(
				p_guid2 = splits2.account_guid
				or
				-- get_account_long_name(splits2.account_guid) like concat( get_account_long_name(p_guid2), ':%')
				is_child_of( splits2.account_guid, p_guid2, ifnull(p_recursive, false) )
			)
			and	splits2.tx_guid in
			(
				select		transactions1.guid
				from
						transactions transactions1
					join 	splits splits1
						on	transactions1.guid = splits1.tx_guid	
				where 				
					p_guid1 = splits1.account_guid
					and	transactions1.post_date >= p_date1
					and 	transactions1.post_date <= p_date2
			)
			and	transactions2.post_date >= p_date1
			and 	transactions2.post_date <= p_date2
	) transaction_set
	limit 1;
	-- p_guid2 regexp concat( '[[:<:]]', splits2.account_guid, '[[:>:]]' )
	-- and		splits1.value_num + splits2.value_num = 0;

	-- call log( 'DEBUG : END get_transactions_value');

	return ifnull(round(l_value,6),0);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] Returns the 'earliest' or 'latest' transaction date in a specified account
-- each transaction has two dates; the 'post' date when the transaction occurred and the 'enter' date when it was added to GnuCash
-- excludes future transactions
-- NOTE the Gnucash GUI displays localtime, but dates in the DB are stored as UTC
drop function if exists get_transaction_date;
//
create function get_transaction_date
	(
		p_guid			varchar(32), 
		p_dimension		varchar(10), -- 'earliest' or 'latest'
		p_field			varchar(10) -- 'enter' or 'post' 
	)
	returns 			timestamp
begin
	declare l_date			timestamp default null;

	-- verify inputs are sane 
	if 	p_guid is null
	or	not exists_account(p_guid)
	then
		call log('WARNING : get_transaction_date aborted. Input values not sane.'); 
		return null;
	end if;

	-- set defaults
	set p_dimension = upper(ifnull(p_dimension, 'LATEST'));
	set p_field = upper(ifnull(p_field, 'POST'));

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	if p_dimension = 'EARLIEST' then

		if p_field = 'ENTER' then

			select	min(enter_date)
			into 	l_date
			from 	transactions
				join 	splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = p_guid
				and 	post_date <= current_timestamp
				and 	enter_date <= current_timestamp;

		else
			select	min(post_date)
			into 	l_date
			from 	transactions
				join 	splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = p_guid
				and 	post_date <= current_timestamp
				and 	enter_date <= current_timestamp;
		end if;

	else

		if p_field = 'ENTER' then

			select	max(enter_date)
			into 	l_date
			from 	transactions
				join 	splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = p_guid
				and 	post_date <= current_timestamp
				and 	enter_date <= current_timestamp;

		else
			select	max(post_date)
			into 	l_date
			from 	transactions
				join 	splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = p_guid
				and 	post_date <= current_timestamp
				and 	enter_date <= current_timestamp;
		end if;

	end if;	

	-- return convert_tz( l_date, get_constant('Default timezone'), 'UTC');
	return round_timestamp(l_date);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] posts a split (part of a transaction) (dangerous!)
-- if p_transaction_guid is specified, adds split to existing transaction
-- otherwise, adds a new transaction
drop function if exists post_split;
//
create function post_split
	(
		p_account_from		varchar(32),
		p_account_to		varchar(32),
		p_value			decimal(20,6),
		p_transaction_guid	varchar(32),
		p_date_posted		timestamp,
		p_description		varchar(2048)
	)
	returns varchar(32)
begin
	declare l_exists		int default 0;
	declare l_guid			varchar(32);
	declare l_default_currency	varchar(32);
	declare l_value_denom		bigint(20);
	declare l_value_num		bigint(20);
	declare l_quantity_denom_from	bigint(20);
	declare l_quantity_num_from 	bigint(20);
	declare l_quantity_denom_to	bigint(20);
	declare l_quantity_num_to 	bigint(20); 
	declare l_all_accounts		text; -- varchar(60000);
	declare	l_count			int default 1;

	-- call log( concat('DEBUG : START post_split(', ifnull(p_account_from, 'null'), ',', ifnull(p_account_to, 'null'), ',', ifnull(p_value, 'null'), ',', ifnull(p_transaction_guid, 'null'), ',', ifnull(p_date_posted, 'null'), ',', ifnull(p_description, 'null'), ')' ));

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');
	
	-- verify inputs are sane 
	if 	not exists_account(p_account_from)
		or not exists_account(p_account_to)
		or p_account_from = p_account_to
		or p_value is null
	then
		call log('WARNING : Post_split aborted. Input values not sane.'); 
		return null;
	end if;

	if p_transaction_guid is not null then

		set l_exists = 0;

		select 	count(*)
		into 	l_exists
		from	transactions
		where	guid = p_transaction_guid;

		if l_exists != 1 then
			call log( concat('WARNING : Post_split aborted. Transaction ', p_transaction_guid, ' does not exist.'));
			return null;
		end if;

	end if;

	-- default values
	set p_date_posted = ifnull(p_date_posted, round_timestamp(current_date));

	-- compile a complete list of accounts in the transaction to better determine what the transaction is for
	set l_all_accounts = 	sort_array(
					concat(
						if( p_transaction_guid is not null, 
							concat(get_transaction_accounts(p_transaction_guid), ','), 
							''
						),
						p_account_from,
						',',
						p_account_to
					),
					'u',
					null
				);

	-- calculate values beforehand so all inserts are as quick as possible
	set l_default_currency 		= get_default_currency_guid();
	set l_value_denom 		= get_commodity_latest_denom( l_default_currency );
	set l_value_num 		= p_value * l_value_denom;
	set l_quantity_denom_to 	= get_commodity_latest_denom( get_account_commodity( p_account_to ));
	set l_quantity_num_to 		= convert_value(p_value, l_default_currency, get_account_commodity( p_account_to ), p_date_posted ) * l_quantity_denom_to; 
	set l_quantity_denom_from 	= get_commodity_latest_denom( get_account_commodity( p_account_from ));
	set l_quantity_num_from 	= convert_value(p_value, l_default_currency, get_account_commodity( p_account_from ), p_date_posted ) * l_quantity_denom_from; 
	
	-- special case when posting capital gains or dividends to or through a STOCK/ASSET account; the quantity is always zero (ie no stocks change hands)
	if 	get_account_type( p_account_to ) in ('ASSET','STOCK')
		or get_account_type( p_account_from ) in ('ASSET','STOCK')
	then
		while_loop : while l_count <= get_element_count(l_all_accounts, null) do
			if 		is_child_of( get_element(l_all_accounts, l_count, null), get_account_guid(get_variable( 'Capital gains account' )),	true)
				or 	is_child_of( get_element(l_all_accounts, l_count, null), get_account_guid(get_variable( 'Dividends account' )),		true)
			then
				if 	get_account_type( p_account_to ) in ('ASSET','STOCK')
				then
					set l_quantity_denom_to = 1;
					set l_quantity_num_to = 0;
				end if;

				if 	get_account_type( p_account_from ) in ('ASSET','STOCK')
				then
					set l_quantity_denom_from = 1;
					set l_quantity_num_from = 0;
				end if;

				leave while_loop;
			end if;

			set l_count = l_count + 1;

		end while;
	end if;

	-- when posting capital gains or dividends for a STOCK/ASSET account then the quantity for the STOCK/ASSET account is 0
/*
	if 	get_account_type( p_account_to ) in ('ASSET','STOCK') 
		and (
			is_child_of( p_account_from, get_account_guid(get_variable( 'Capital gains account' )),true)
			or is_child_of( p_account_from, get_account_guid(get_variable( 'Dividends account' )),true)
		)
	then
		set l_quantity_denom_to = 1;
		set l_quantity_num_to = 0;
	else 
		set l_quantity_denom_to = get_commodity_latest_denom( get_account_commodity( p_account_to ));
		set l_quantity_num_to = convert_value(p_value, l_default_currency, get_account_commodity( p_account_to ), p_date_posted ) * l_quantity_denom_to; 
	end if;

	if 	get_account_type( p_account_from ) in ('ASSET','STOCK') 
		and (
			is_child_of( p_account_to, get_account_guid(get_variable( 'Capital gains account' )),true)
			or is_child_of( p_account_to, get_account_guid(get_variable( 'Dividends account' )),true)
		)
	then
		set l_quantity_denom_from = 1;
		set l_quantity_num_from = 0;
	else 
		set l_quantity_denom_from = get_commodity_latest_denom( get_account_commodity( p_account_from ));
		set l_quantity_num_from = convert_value(p_value, l_default_currency, get_account_commodity( p_account_from ), p_date_posted ) * l_quantity_denom_from; 
	end if;
*/

	-- the subsequent insert statements are either *all* committed or *none* are committed
	-- start transaction; -- cat do this; a trigger or function calls this procedure, and they disallow transactions

	-- add a transaction if required
	if 	p_transaction_guid is null
		and gnc_lock('transactions') 
	then
		set p_transaction_guid = new_guid();

		insert into transactions 
			(guid, currency_guid, post_date, enter_date, description)
		values
			(	p_transaction_guid, 
				l_default_currency, 
				p_date_posted, 
				current_date, 
				ifnull(p_description, concat('Transaction added by customgnucash.post_split on ', current_date))
			);

		call log( concat('INFORMATION : Added transaction ' , p_transaction_guid ));
		call gnc_unlock('transactions');
	end if;

	-- always add 2 splits, one for each side of the transaction
	if gnc_lock('splits') then

		set l_guid = new_guid();

		insert into splits
			(	guid, 
				tx_guid, 
				account_guid, 
				memo,
				reconcile_state, 
				reconcile_date,
				value_num, 
				value_denom, 
				quantity_num, 
				quantity_denom,
				lot_guid
			)
		values
			(	l_guid, 
				p_transaction_guid, 
				p_account_from,
				ifnull(p_description, concat('Split added by customgnucash.post_split on ', current_date)),
				'n', 
				null,
				- l_value_num,
				l_value_denom,
				- l_quantity_num_from,
				l_quantity_denom_from,
				null
			);
		call log( concat('INFORMATION : Added split ' , l_guid , ' to transaction ' , p_transaction_guid ));

		set l_guid = new_guid();
		insert into splits
			(	guid, 
				tx_guid, 
				account_guid, 
				memo,
				reconcile_state, 
				reconcile_date,
				value_num, 
				value_denom, 
				quantity_num, 
				quantity_denom,
				lot_guid
			)
		values
			(	l_guid, 
				p_transaction_guid, 
				p_account_to, 
				ifnull(p_description, concat('Split added by customgnucash.post_split on ', current_date)),
				'n', 
				null,
				l_value_num,
				l_value_denom,
				l_quantity_num_to,
				l_quantity_denom_to,
				null
			);
		call log( concat('INFORMATION : Added split ' , l_guid , ' to transaction ' , p_transaction_guid ));

		call gnc_unlock('splits') ;
	
	end if;

	-- call log('DEBUG : END post_split');

	return p_transaction_guid;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [F] ACCOUNT ROUTINES

-- [R] returns true if given account name can be found in GnuCash
-- input can be a name or a guid
drop function if exists exists_account;
//
create function exists_account
	(
		p_in 		text -- varchar(60000)
	)
	returns 		boolean
begin
	declare l_count 	int;

	-- check sane values
	if p_in is null
	then
		return null;
	else
		-- standardise input (uppercase, trimmed of spaces and account separators
		set p_in = trim( upper( trim( get_constant('Account separator') from p_in) ) );
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	if	is_guid(p_in)
	then
		-- p_in is probably a guid

		select 	count(guid)
		into 	l_count
		from 	accounts
		where 	upper( trim( guid )) = p_in;

	else
		-- p_in is probably a name

		if locate(get_constant('Account separator'), p_in ) = 0 then

			select 	count(guid)
			into 	l_count
			from 	accounts
			where 	upper( trim( name)) = p_in;

		else

			select 	count(guid)
			into 	l_count
			from 	account_map
			where 	long_name like concat('%',  p_in);

		end if;

	end if;

	if l_count = 0 then 
		return false;
	else 
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if the account identified (by guid) is a placeholder
drop function if exists is_placeholder;
//
create function is_placeholder
	(
		p_guid 	varchar(32)
	)
	returns 	boolean
begin
	declare l_placeholder int;

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	accounts.placeholder
	into 	l_placeholder 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;
	
	return l_placeholder;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if account is (or has been) in use; ie, it has transactions
drop function if exists is_used;
//
create function is_used
	(
		p_guid 	varchar(32)
	)
	returns 	boolean
begin
	declare l_count int;

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('splits', 'WAIT');

	select 	count(*)
	into 	l_count
	from 	splits
	where 	account_guid = p_guid;

	if l_count = 0 then 
		return false;
	else 
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if the account identified (by guid) is hidden
drop function if exists is_hidden;
//
create function is_hidden
	(
		p_guid 	varchar(32)
	)
	returns 	boolean
begin
	declare l_hidden int;

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	accounts.hidden
	into 	l_hidden 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;
	
	return l_hidden;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if the account identified (by guid) is a parent account
drop function if exists is_parent;
//
create function is_parent
	(
		p_guid varchar(32)
	)
	returns boolean
begin
	declare l_count int;

	-- call log( concat('DEBUG : START is_parent(', ifnull(p_guid, 'null'), ')' ));

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select 	count(accounts.guid)
	into 	l_count
	from 	accounts accounts
	where 	accounts.parent_guid = p_guid;

	-- call log('DEBUG : END is_parent');
	
	if l_count = 0 then	
		return false;
	else 
		return true;
	end if;
	
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if the account identified (by guid) is a child account
drop function if exists is_child;
//
create function is_child
	(
		p_guid varchar(32)
	)
	returns boolean
begin
	declare l_parent_type varchar(32);

	-- call log( concat('DEBUG : START is_child(', ifnull(p_guid, 'null'), ')' ));

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select 	get_account_type(parent_guid)
	into	l_parent_type
	from	accounts accounts
	where	accounts.guid = p_guid
	limit 1;

	-- call log('DEBUG : END is_child');

	if l_parent_type is null or l_parent_type = 'ROOT' then 
		return false;
	else 
		return true;
	end if;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the guid of the first account found with the specified name
-- if there more than one account matches, an arbitrarily chosen one is returned
drop function if exists get_account_guid;
//
create function get_account_guid
	(
		p_name 			varchar(2048)
	)
	returns varchar(32)
	deterministic
begin
	declare l_guid varchar(32);

	-- call log( concat('DEBUG : START get_account_guid(', ifnull(p_name, 'null'), ')' ));

	-- sanity check
	if p_name is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	set p_name = upper( trim( get_constant('Account separator') from p_name));

	if locate(get_constant('Account separator'), p_name) = 0 then

		select distinct guid
		into 	l_guid
		from 	accounts accounts
		where 	upper( trim( accounts.name)) = p_name
		limit 	1;

	else

		select distinct guid
		into 	l_guid
		from 	account_map
		where 	long_name like ( concat('%', p_name ))
		limit 	1;

	end if;

	-- call log('DEBUG : START get_account_guid');

	return trim(l_guid);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns  guid of root account (ASSETS, INCOME, EQUITY, EXPENSE etc)
drop function if exists get_account_root;
//
create function get_account_root
	(
		p_guid varchar(32)
	)
	returns varchar(32)
begin
	declare l_guid	varchar(32);

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select	root_guid
	into l_guid
	from account_map
	where guid = p_guid
	limit 1;

	return l_guid;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the short name of account identified (by guid)
drop function if exists get_account_short_name;
//
create function get_account_short_name
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
	deterministic
begin
	declare l_name varchar(2048);

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	trim( upper( accounts.name ))
	into 	l_name 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return l_name;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the full, qualified, name of account identified (by guid)
-- the long name includes parent account names also
-- account names are separated by the 'Account separator' variable
drop function if exists get_account_long_name;
//
create function get_account_long_name
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
	deterministic
begin
	declare l_name varchar(2048);

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	trim( upper( account_map.long_name )) 
	into 	l_name 
	from 	account_map
	where 	account_map.guid = p_guid 
	limit 	1;

	return l_name;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the guid of the native currency of the accounts commodity
-- this will be a currency, and never a stock
-- a convenience function; merely calls get_commodity_currency with the correct parameters
drop function if exists get_account_currency;
//
create function get_account_currency
	(
		p_guid varchar(32)
	)
	returns varchar(32)
begin
	return get_commodity_currency( get_account_commodity( p_guid ));
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns the account type
-- note that indices, such as XAU (gold), are stored in GnuCash as 'currencies', which they aren't really
drop function if exists get_account_type;
//
create function get_account_type
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
begin
	declare l_type varchar(2048);

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	select distinct	accounts.account_type 
	into 	l_type
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return trim(l_type);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns a csv string listing children of the identified account (in no particular order)
-- p_recursive=false - direct children only
-- p_recursive=true - all children, direct and indirect
drop function if exists get_account_children;
//
create function get_account_children
	(
		p_guid 			varchar(32),
		p_recursive		boolean
	)
	returns text -- varchar(60000)
begin
	declare l_guid 			text; -- varchar(60000);
	declare l_long_name		varchar(2048);

	-- call log( concat('DEBUG : START get_account_children(', ifnull(p_guid, 'null'), ',', ifnull(p_recursive, 'null'), ')' ));

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	set p_recursive = ifnull(p_recursive, false);

	-- direct children only
	if p_recursive = false then

		select 	group_concat(distinct children.guid)
		into 	l_guid
		from 	accounts accounts
			left outer join accounts children
				on accounts.guid = children.parent_guid
		where 	accounts.guid = p_guid 
		limit 	1;
	
	-- all children
	else

		set l_long_name = get_account_long_name(p_guid);

		select 	group_concat( distinct guid)
		into 	l_guid
		from 	account_map
		where 	long_name like ( concat( l_long_name, ':%' ))
		limit 1;

	end if;

	-- call log('DEBUG : END get_account_children');

	return trim(l_guid);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns CSV string containing parent account guids (in child->parent order)
drop function if exists get_account_parents;
//
create function get_account_parents
	(
		p_guid 			varchar(32),
		p_recursive		boolean
	)
	returns varchar(2048)
begin
	declare l_all_parents 		varchar(2048);
	declare l_parent 		varchar(32);
	declare l_child			varchar(32);

	-- call log( concat('DEBUG : START get_account_parents(', ifnull(p_guid, 'null'), ',', ifnull(p_recursive, 'null'), ')' ));

	-- sanity check
	if 	p_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	set p_recursive = ifnull(p_recursive, false);

	-- direct parent (singular) only
	select distinct	accounts.parent_guid 
	into 	l_parent
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	call put_element(l_all_parents, l_parent, ',');
	set l_child = l_parent;

	-- if recursive has been selected, then look further ...
	if p_recursive then

		while is_child(l_child) do

			select distinct	accounts.parent_guid 
			into 	l_parent
			from 	accounts accounts
			where 	accounts.guid = l_child 
			limit 	1;

			call put_element(l_all_parents, l_parent, ',');
			set l_child = l_parent;

		end while;

	end if;

	-- call log('DEBUG : END get_account_parents');
	
	return trim(',' from l_all_parents);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns true if p_guid_child is a child of p_guid_parent
-- p_recursive=false : returns true only if relationship is direct
-- p_recursive=true : returns true however indirect relationship
drop function if exists is_child_of;
//
create function is_child_of
	(
		p_child_guid 	varchar(32),
		p_parent_guid 	varchar(32),
		p_recursive	boolean
	)
	returns boolean
	-- deterministic
begin
	declare l_parent_guid	varchar(32);

	-- call log( concat('DEBUG : START is_child_of(', ifnull(p_child_guid, 'null'), ',', ifnull(p_parent_guid, 'null'), ',', ifnull(p_recursive, 'null'), ')' ));

	-- sanity check
	if 	p_child_guid is null
		or p_parent_guid is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	-- do simple check first
	select 	parent_guid
	into 	l_parent_guid
	from 	accounts accounts
	where 	accounts.guid = p_child_guid;

	if 	l_parent_guid = p_parent_guid 
		or ( -- if simple check (above) returned nothing and a recursive check was requested, look further...
			ifnull(p_recursive, false)
			and get_account_children(p_parent_guid, true) regexp concat( '[[:<:]]', p_child_guid, '[[:>:]]' ) 
			-- if locate( get_account_long_name(p_parent_guid), get_account_long_name(p_child_guid) ) > 0
		)
	then
		return true;
	end if;
	
	-- call log('DEBUG : END is_child_of');

	-- if nothing found by this point, return false
	return false;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] returns specified user defined attribute values from a given account
-- user defined attributes are entered into the GnuCash GUI account notes field thus : 
-- "[<attribute name>=<attribute value>,<attribute name>=<attribute value>,...]" 
-- they are inherited from parent accounts too (the lower account takes precedence)
drop function if exists get_account_attribute;
//
create function get_account_attribute
	(
		p_guid			varchar(32),
		p_attribute		varchar(32)
	)
	returns varchar(2048)
begin
	declare l_all_attributes	varchar(2048);
	declare l_attributes		varchar(2048);
	declare l_attribute_value	varchar(2048);
	declare l_accounts		varchar(2048);
	declare l_counter		int default 1;

	-- sanity check
	if 	p_guid is null
		or p_attribute is null
	then
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts, slots', 'WAIT');

	-- get a list of accounts to interrogate
	call put_element(l_accounts, p_guid, ',');
	call put_element(l_accounts, get_account_parents(p_guid, true), ',');

	while l_counter <= get_element_count(l_accounts, ',') do

		select 
				upper( 
					trim( 
						substring( 
							slots.string_val,
							locate('[', slots.string_val) + 1,
							locate(']', slots.string_val) - locate('[', slots.string_val) - 1
						)
					)
				)
		into
				l_attributes
		from 
				accounts accounts
			join 	slots slots on accounts.guid = slots.obj_guid and slots.name = 'notes'
		where 	accounts.guid = get_element(l_accounts, l_counter, ',');

		call put_element(l_all_attributes, l_attributes, ',');
		set l_counter = l_counter + 1;

	end while;

	-- if there are any attributes at all ...
	if length(l_all_attributes) > 0 then
		set l_counter = 1;

		-- wind through attribute string to find the one we are looking for (return only the first one)
		attribute_loop : while l_counter <= get_element_count( l_all_attributes, ',') do
			if 	upper( trim( p_attribute)) = get_element( get_element( l_all_attributes , l_counter, ',' ), 1, '=') then
				-- append found attribute value to list of attribute values
				call put_element( 	l_attribute_value, 
							get_element( get_element( l_all_attributes , l_counter, ',' ), 2,'='),
							','	);
				leave attribute_loop;
			end if;
			set l_counter = l_counter + 1;
		end while;
	end if;

	return l_attribute_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] Returns name of 'parallel' account
-- a 'parallel' account is, for example, the capital gains, interest or dividend income account associated with an asset account
-- e.g. the dividend account associated with 'ASSETS:A:B' is assumed to be "get_variable('Dividend account'):A:B" (probably 'INCOME:DIVIDENDS:A:B')
-- if p_parallel_root = 'CASH' then returns the expected CASH- or BANK-type sibling account to p_source_account_guid (for use in dividend transactions, for example)
drop function if exists get_related_account;
//
create function get_related_account
	(
		p_source_account_guid	varchar(32),
		p_parallel_root		varchar(2048) -- eg "get_variable('Capital gains account')"
	)
	returns varchar(2048)
begin
	declare l_count 		int default 0;
	declare l_parallel_account_name	varchar(2048);

	-- call log( concat(	'DEBUG : START get_related_account(', 
	--			ifnull(p_source_account_guid, 'null'), ',', 
	--			ifnull(p_parallel_root, 'null'), ')'
	--	));

	set l_count = get_element_count( get_account_long_name(p_source_account_guid), get_constant('Account separator'));

	if l_count > 1
	then
		-- calculate parallel account name
		if p_parallel_root = 'CASH'
		then
			set l_parallel_account_name = concat(	
							substring_index( get_account_long_name(p_source_account_guid), get_constant('Account separator'), (l_count-1 ) ), 
							get_constant('Account separator'), 
							'CASH'
							);
		else
			set l_parallel_account_name = concat( 	
							p_parallel_root, 
							get_constant('Account separator'), 
							substring_index( get_account_long_name(p_source_account_guid), get_constant('Account separator'), -(l_count-1 ) )
							);
		end if;
		-- call log(concat('DEBUG : l_parallel_account_name=', l_parallel_account_name));
	end if;

	-- call log('DEBUG : END get_related_account');

	return l_parallel_account_name;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] totals up values in a single account (when p_children=false), or an account and its subaccounts (when p_children=true)
-- between two dates (default : from beginning of time to now), 
-- and returns the value converted to a standard currency, if specified, or required (ie when p_children=true) when the default curency is used
drop function if exists get_account_value;
//
create function get_account_value
	(
		p_guid			varchar(32),
		p_currency		varchar(32),
		p_date1			timestamp,
		p_date2			timestamp,
		p_children		boolean
	)
	returns decimal(20,6)
begin
	declare l_acct_value 		decimal(20,6) default null;
	declare l_parent_acct 		varchar(2048);
	declare l_date 			timestamp;
	declare l_variable_name		varchar(250);
	declare l_account_commodity	varchar(32);

/*	call log( concat(	'DEBUG : START get_account_value(', 
				ifnull(p_guid, 'null'), ',', 
				ifnull(p_currency, 'null'), ',', 
				ifnull(p_date1, 'null'), ',', 
				ifnull(p_date2, 'null'), ',', 
				ifnull(p_children, 'null'), ')'
		));
*/
	-- bail if no account specified
	if p_guid is null then
		return null;
	end if;

	-- short circuit if no transactions in account
	if p_children = false and not is_used(p_guid) then
		return 0;
	end if;

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	set l_account_commodity = get_account_commodity(p_guid);

	-- if we are adding up children accts also, standardise on default currency
	if p_children = true and p_currency is null then
		set p_currency = get_default_currency_guid();
	else
		-- otherwise just use whatever the account uses (which might be share units) if no currency specified
		set p_currency = ifnull(p_currency, l_account_commodity );
	end if;

	-- set defaults
	set p_children = ifnull(p_children, false);
	-- set p_date1 = get_transaction_date(p_guid, 'EARLIEST', 'POST'); -- not meaningful for parent accounts
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions;
	 end if;

	-- if the currency requested (p_currency) is the same as the commodity (or currency) native to the account, the account value won't change after the latest posted transaction, otherwise choose the date of the latest price of the accounts commodity
	if p_children = true then
		set p_date2 = ifnull( p_date2, round_timestamp(current_timestamp)); 
	else
		set p_date2 = ifnull(
					p_date2, 
					if( 	p_currency = l_account_commodity ,
						get_transaction_date(p_guid, 'LATEST', 'POST'),
						-- get_commodity_latest_date(l_account_commodity)
						round_timestamp(current_timestamp)
					)
				);
	end if;

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	set l_variable_name = concat('get_account_value(', p_guid, ',', p_currency, ',', p_date1, ',', p_date2, ',', p_children, ')' );

	-- check if value has already been calculated, and is still valid
	if get_variable('Recalculate') = 'N' then

		if 	exists_variable(l_variable_name)
		and 	get_variable_date(l_variable_name) >= get_transaction_date(p_guid, 'LATEST', 'ENTER')
		then
			set l_acct_value = get_variable(l_variable_name);
		end if;

	end if;

	-- if value has not already been calculated...
	if l_acct_value is null then

		-- if no children account rollup is required (or possible), do a simple sum
		if p_children = false or is_parent(p_guid) is false then

			select		sum(splits.quantity_num/splits.quantity_denom)
			into 		l_acct_value
			from 		splits splits
				join 	transactions transactions 
					on 	splits.tx_guid = transactions.guid
			where 		splits.account_guid = p_guid
				and	round_timestamp(transactions.post_date) >= p_date1
				and 	round_timestamp(transactions.post_date) <= p_date2;

			-- convert to specified currency, if any
			if p_currency != get_account_commodity(p_guid) then
				set l_acct_value = convert_value(l_acct_value, l_account_commodity, p_currency, p_date2);
			end if;

		-- child rollup requested
		else

			-- if specified account is a top-level account, do shortcut calculation (without regexp)
			if is_child(p_guid) is false then

				select		sum( 
							convert_value(
								splits.quantity_num/splits.quantity_denom, 
								get_account_commodity(splits.account_guid), 
								p_currency, 
								p_date2
							)
						)
				into 		l_acct_value
				from 		splits splits
					join 	transactions transactions 
						on 	splits.tx_guid = transactions.guid
					join 	account_map 
						on 	splits.account_guid = account_map.guid
				where 		account_map.root_guid = p_guid
					and	 	round_timestamp(transactions.post_date) >= p_date1
					and		round_timestamp(transactions.post_date) <= p_date2;
		
			-- not a top-level account, so do the calculation the long way
			else

				set l_parent_acct = concat('^', get_account_long_name(p_guid), ':');
			
				-- otherwise sum up all accts that include the accts long name 
				select 		sum(
								convert_value(
									splits.quantity_num/splits.quantity_denom, 
									get_account_commodity(splits.account_guid), 
									p_currency, 
									p_date2
								)
							)
				into 		l_acct_value
				from 		splits splits
					join 	transactions transactions 
						on 	splits.tx_guid = transactions.guid
					join 	account_map 
						on 	splits.account_guid = account_map.guid
				where 		(
								account_map.guid = p_guid
								or account_map.long_name regexp (l_parent_acct)
							)
					and	 	round_timestamp(transactions.post_date) >= p_date1
					and		round_timestamp(transactions.post_date) <= p_date2;

				end if;
		end if;

		set l_acct_value = ifnull(round(l_acct_value,6),0);

		-- store the new result for future use
		call delete_series('get_account_value', concat('1=', p_guid)); 
		call post_variable(l_variable_name, l_acct_value);

	end if;

	-- call log( 'DEBUG : END get_account_value');

	return l_acct_value;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] totals up units (ie, shares) in a single account 
-- between two dates (default : from beginning of time to now)
-- just a convenience function; merely calls get_account_value with correct parameters
drop function if exists get_account_units;
//
create function get_account_units
	(
		p_guid			varchar(32),
		p_date1			timestamp,
		p_date2			timestamp
	)
	returns decimal(20,6)
begin
	return 	get_account_value( 
				p_guid, 
				get_account_commodity(p_guid), 
				p_date1,
				p_date2, 
				false);
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [R] Calculates three "costs" of an account
-- for use in calculating unrealised gains, or as a denominator in %age gain calcs 
-- v slow and probably inefficient! (although it stores the result in case it is needed again)
-- this is really part of the report_account_gains function, but its so complex that it was easier to develop when split out from it
drop procedure if exists get_account_costs;
//
create procedure get_account_costs
	(
		in p_guid			varchar(32),
		in p_date1			timestamp,
		in p_date2			timestamp,

		out	p_remainder_cost	decimal(20,6), -- STOCK/ASSET : the original cost of what has *not* been sold (for use in calculating unrealised gains)
		out	p_sold_cost		decimal(20,6), -- STOCK/ASSET : the original cost of what *has* been sold (for use in calculating %age realised gains)
		out	p_average_cost		decimal(20,6)  -- BANK/CASH/STOCK/ASSET : the average cost of an account, at times of dividend or interest payments 
	)
procedure_block : begin

	declare l_stock_split_ratio		decimal(20,6);
	declare	l_expense			decimal(20,6);
	-- declare l_date			timestamp;
	declare l_previous_transaction_guid	varchar(32);
	declare	l_variable_name			varchar(250);

	-- variables for holding transaction cursor output
	declare l_transaction_guid 		varchar(32);
	declare	l_post_date			timestamp;
	declare l_action			varchar(32);
	declare	l_class				varchar(32);
	declare l_quantity 			decimal(20,6);
	declare l_value 			decimal(20,6);
	declare l_transactions_done 		boolean default false;
	declare l_transactions_done_temp 	boolean default false;

	-- variables for holding  tally cursor output
	declare l_tally_transaction_guid_bought	varchar(32);
	declare l_tally_quantity_bought 	decimal(20,6);
	declare l_tally_quantity_sold 		decimal(20,6);
	declare l_tally_done 			boolean default false;
	declare l_tally_done_temp		boolean default false;

	-- outer block cursors
	declare lc_transaction cursor for
		select distinct
			transactions.guid,
			round_timestamp(transactions.post_date),
			upper(splits.action),
			case
				when splits.account_guid = p_guid										then '3.SELF'
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Dividends account')), true) 		then '2.DIVIDEND'
				-- when is_child_of(splits.account_guid, get_account_guid( get_variable('Capital gains account')), true) 	then '2.CAPITAL GAIN'
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Interest account')), true) 		then '2.INTEREST'
				else concat('1.', get_account_type(splits.account_guid))
			end as class,
			splits.quantity_num / splits.quantity_denom,
			convert_value(
				splits.value_num / splits.value_denom,
				transactions.currency_guid,
				get_default_currency_guid(),
				transactions.post_date
			)
		from
			transactions
			join splits 
				on transactions.guid = splits.tx_guid
					and transactions.guid in 
						(	select 	splits.tx_guid 
							from 	splits 
							where 	splits.account_guid = p_guid
						)
		where
			splits.quantity_num != 0
			and round_timestamp(transactions.post_date) <= p_date2
		order by
			transactions.post_date,
			transactions.enter_date,
			class;

	declare continue handler for not found set l_transactions_done =  true;

	-- call log( concat('DEBUG : START get_account_costs(', ifnull(p_guid, 'null'), ',', ifnull(p_date1, 'null'), ',', ifnull(p_date2, 'null'), ')'));

	-- try to play nicely with other procedures
	do is_locked('transactions, splits', 'WAIT');

	-- use earliest and latest transaction dates if none provided
	set p_date2 = round_timestamp(ifnull(p_date2, get_transaction_date(p_guid, 'LATEST', 'POST')));
	set p_date1 = round_timestamp(ifnull(p_date1, get_transaction_date(p_guid, 'EARLIEST', 'POST')));
	
/*	if p_date2 is null then

		select 	max(post_date)
		into 	p_date2
		from 	transactions
			join splits 
				on transactions.guid = splits.tx_guid
		where 	splits.account_guid = p_guid
		and 	post_date <= current_timestamp;

	end if;

	if p_date1 is null then

		select 	min(post_date)
		into 	p_date1
		from 	transactions
			join splits 
				on transactions.guid = splits.tx_guid
		where 	splits.account_guid = p_guid
		and 	post_date <= p_date2;

	end if;

	-- standardise dates
	set p_date1 = round_timestamp(p_date1);
	set p_date2 = round_timestamp(p_date2);
*/	

	set l_variable_name = concat('get_account_costs(', p_guid, ',', p_date1, ',', p_date2, ')');

	-- check if values have already been calculated (and are still valid)
	if get_variable('Recalculate') = 'N' then

		if 	exists_variable(concat(l_variable_name, '.p_remainder_cost' ))
		and	get_variable_date(concat(l_variable_name, '.p_remainder_cost' )) >= get_transaction_date(p_guid, 'LATEST', 'ENTER')
		then
			set p_remainder_cost = get_variable(concat(l_variable_name, '.p_remainder_cost'));
		end if;

		if 	exists_variable(concat(l_variable_name, '.p_sold_cost' )) 
		and	get_variable_date(concat(l_variable_name, '.p_sold_cost' )) >= get_transaction_date(p_guid, 'LATEST', 'ENTER')
		then
			set p_sold_cost = get_variable(concat(l_variable_name, '.p_sold_cost'));
		end if;

		if 	exists_variable(concat(l_variable_name, '.p_average_cost' )) 
		and	get_variable_date(concat(l_variable_name, '.p_average_cost' )) >= get_transaction_date(p_guid, 'LATEST', 'ENTER')
		then
			set p_average_cost = get_variable(concat(l_variable_name, '.p_average_cost'));
		end if;

	end if;

	-- only calculate costs if not already done for this account type
	if 	(get_account_type(p_guid) in ('STOCK', 'ASSET')
		and 	(
			p_remainder_cost is null
			or p_sold_cost	is null
			)
		)
		or p_average_cost 	is null
	then

		-- temp table to keep a running tally of what's actually in the stock/asset account
		drop temporary table if exists stock_tally;
		create temporary table stock_tally (
			id			smallint not null auto_increment,
			transaction_guid_bought	varchar(32),
			post_date_bought	timestamp default 0,
			quantity_bought		mediumint,
			unit_value_bought	decimal(20,6),
			quantity_sold		mediumint,
			primary key (id)
		);

		-- temp table to keep track of account costs at times of dividend and interest payments
		drop temporary table if exists cost_tally;
		create temporary table cost_tally (
			account_cost			decimal(20,6)
		);

		-- set output parms to 0
		set p_remainder_cost	= 0;
		set p_sold_cost		= 0;
		set p_average_cost	= 0;

		open lc_transaction;

		-- make sure cursor no-data flag is false
		set l_transactions_done =  false;

		transaction_loop : loop

			-- call log('START: transaction_loop');

			fetch lc_transaction into 
				l_transaction_guid,
				l_post_date,
				l_action,
				l_class,
				l_quantity,
				l_value;

			if l_transactions_done then 
				-- call log('LEAVE transaction_loop');
				leave transaction_loop;
			else
				-- remember flag in case it gets munged by intervening DB operations
				set l_transactions_done_temp = l_transactions_done;
			end if;

			-- reset on new transaction
			if l_previous_transaction_guid is null or l_previous_transaction_guid != l_transaction_guid then		
				set l_expense = 0;
			end if;

			if get_account_type(p_guid) in ('STOCK', 'ASSET') then

				-- take a note of expenses for use in later calculation
				if l_class regexp 'EXPENSE'	then 
					set l_expense = ifnull(l_expense,0) + l_value;
				end if;

				-- calculate cost of account whenever there is a dividend payment
				if 	l_class regexp 'DIVIDEND' 
				and 	l_post_date >= p_date1
				then 
					
					insert into cost_tally
					(	
						select ifnull( sum( (quantity_bought - quantity_sold) * unit_value_bought ), 0)
						from stock_tally
					);

				end if;

				if l_class regexp 'SELF' then
								
					-- when adding value, add a new row to the running tally
					-- only +ve quantities are ever posted to the tally table
					if l_quantity > 0 then

						insert into stock_tally
							(
								transaction_guid_bought,
								post_date_bought,
								quantity_bought,
								unit_value_bought,
								quantity_sold
							)
						values 
							( 
								l_transaction_guid, 
								l_post_date,
								l_quantity, 
								abs(l_value + l_expense)/l_quantity,
								0
							);

					-- when selling value, run through the tally in date order
					else
		
						-- if the reduction in quantity is a 'split' rather than a true sale, the the tally needs to be retrospectively fixed
						if locate('SPLIT', l_action) != 0 then

							--  calculate the split ratio from the quantity immediately before the split
							select 	(quantity_bought + l_quantity) / quantity_bought
							into 	l_stock_split_ratio
							from 	stock_tally
							where 	post_date_bought < l_post_date
							limit 1;

							-- update portfolio before this date with ratio (quantity goes down, unit value goes up, total value is the same)
							update 	stock_tally
							set 	quantity_bought 	= quantity_bought 	* l_stock_split_ratio,
								quantity_sold 		= quantity_sold 	* l_stock_split_ratio,
								unit_value_bought 	= unit_value_bought 	/ l_stock_split_ratio
							where 	post_date_bought 	<= l_post_date;

						-- non-split sellings needs a totting up of the values in the tally table
						else

							-- remove -ve sign, to aid clear calculations ...
							set l_quantity = abs(l_quantity);
									
							-- need a new block for tally cursor
							tally_block : begin -- tally block

								declare lc_tally cursor for
									select distinct
										transaction_guid_bought,
										quantity_bought,
										quantity_sold
									from stock_tally
									where quantity_bought - quantity_sold != 0
									order by id;
							
								declare continue handler for not found set l_tally_done =  true;
									
								-- call log('START : tally_block');

								open lc_tally;
								set l_tally_done = false;

								-- when selling stock, sell the earliest first
								tally_loop : loop

									-- call log('START : tally_loop');

									fetch lc_tally into 
										l_tally_transaction_guid_bought,
										l_tally_quantity_bought,
										l_tally_quantity_sold;
											
									-- stop processing if there's no data or the quantity being sold has been entirely processed
									if l_tally_done or l_quantity = 0 then 
										-- call log('LEAVE tally_loop');
										leave tally_loop;
									else
										set l_tally_done_temp = l_tally_done;
									end if;

									-- if the quantity being sold is more than the quantity left in the tally row... 
									if l_quantity >= (l_tally_quantity_bought - l_tally_quantity_sold) then

										update 	stock_tally
										set 	quantity_sold = quantity_bought
										where	transaction_guid_bought = l_tally_transaction_guid_bought;
													
										-- decrease quantity being sold by tally amount
										set l_quantity = l_quantity - (l_tally_quantity_bought - l_tally_quantity_sold);
												
									-- if the quantity being sold (or left over) is less than the tally row
									-- do a partial calculation (only really applies to ASSET types relating to commodities; STOCKs are usually integers)
									else
				
										-- reduce tally row
										update 	stock_tally
										set 	quantity_sold = quantity_sold + l_quantity
										where 	transaction_guid_bought = l_tally_transaction_guid_bought;

										-- we've 'used up' the amount that was sold
										set l_quantity = 0;

									end if; -- if l_quantity >= l_tally_quantity
								
								end loop; -- tally_loop

								close lc_tally;

								-- call log('END : tally_block');

								set l_tally_done = l_tally_done_temp;

							end; -- tally block		
										
						end if; -- if locate('SPLIT', l_action) != 0

					end if; -- if l_quantity > 0

				end if; -- if l_class = "SELF"

			elseif get_account_type(p_guid) in ('CASH', 'BANK') then

				-- calculate cost of account (excluding interest payments) whenever there is an interest payment
				if l_class regexp 'INTEREST' 
					and l_post_date >= p_date1
					then 

					insert into cost_tally
					values
					( 	get_account_value(p_guid, null, null, l_post_date, false)
						-
						get_transactions_value( 
							p_guid, 
							get_account_guid(get_related_account(p_guid, get_variable('Interest account'))), 
							null, 
							null, 
							l_post_date, 
							false)
						+
						get_transactions_value( 
							p_guid, 
							get_account_guid( get_variable('Income tax (interest) paid account')), 
							null, 
							null, 
							l_post_date, 
							false)
					);

				end if;

			end if;

			-- set flag back to what it was before intervening DB operations
			set l_transactions_done = l_transactions_done_temp;

			-- keep track of what transaction we're in
			set l_previous_transaction_guid = l_transaction_guid;

			-- call log('END: transaction_loop');

		end loop; -- transaction_loop

		close lc_transaction;

		-- delete any previously stored version of costs for this account (which are now out-of-date)
		call delete_series('get_account_costs', concat('1=', p_guid)); 

		if get_account_type(p_guid) in ('STOCK', 'ASSET') then

			-- calculate original cost of whatever's left in the account
			select 	ifnull( sum( (quantity_bought - quantity_sold) * unit_value_bought ), 0)
			into 	p_remainder_cost
			from 	stock_tally;

			-- store the new result for future use
			call post_variable(concat(l_variable_name, '.p_remainder_cost'), p_remainder_cost);

			-- calculate original cost of whatever's sold from the account
			select 	ifnull( sum( quantity_sold * unit_value_bought ), 0)
			into 	p_sold_cost
			from 	stock_tally;

			-- store the new result for future use
			call post_variable(concat(l_variable_name, '.p_sold_cost'), p_sold_cost);

		end if;

		-- calculate average cost (at times of dividend or interest payments) over period
		-- this is not likely to be an accurate method of getting %age returns on dividends or interest payments
		select 	ifnull(avg(account_cost), 0)
		into 	p_average_cost
		from 	cost_tally
		where 	account_cost > 0;

		-- store the new result for future use
		call post_variable( concat(l_variable_name, '.p_average_cost'), p_average_cost);

	end if; -- if p_remainder_cost is null

	-- call log('DEBUG : END get_account_costs');

end; -- outer block
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [RW] Creates specified GnuCash account, including any missing parent accounts (using get_variable('Account separator') 
-- uses parent account type and currency if none specified
-- implicit commit in 'insert' requires this to be a procedure 
drop function if exists post_account;
//
create function post_account
	(
		p_name			varchar(2048), -- eg 'ASSETS:THINGY:WOTSOT:DOOBREY'
		p_account_type		varchar(2048),
		p_commodity_guid	varchar(32)
	)
	returns varchar(32)
begin
	declare l_guid			varchar(32) default null;
	declare l_parent_guid		varchar(32);
	declare l_short_name		varchar(2048);
	declare l_long_name		text; -- varchar(60000);
	declare l_account_type		varchar(2048);
	declare l_commodity_guid	varchar(32);
	declare l_commodity_scu		int(11);
	declare l_placeholder		int(11);
	declare l_count			int default 2;
	declare l_account_count		int default 0; 

	-- call log( concat('DEBUG : START post_account(', ifnull(p_name, 'null'), ',', ifnull(p_account_type, 'null'), ',', ifnull(p_commodity_guid, 'null'), ')'));

	-- initialise
	set p_name = trim( trim( get_constant('Account separator') from replace(p_name, '::', ':') ));
	set l_account_count = get_element_count(p_name, get_constant('Account separator'));
	set l_parent_guid = get_account_guid( substring_index(p_name, get_constant('Account separator'), 1 ));

	-- check inputs
	if 	p_name is null
		or l_account_count < l_count
		or l_parent_guid is null
	then
		call log('ERROR : input values not valid');
		return null;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	-- wind through specified account name, creating any missing ones (except first one, which must *already* exist)
	while l_count <= l_account_count do

		set l_long_name =  trim( substring_index( p_name, get_constant('Account separator'), l_count ));
		set l_short_name = trim( substring_index( l_long_name, get_constant('Account separator'), -1 ));

		if 	l_short_name is not null
			and length(l_short_name) > 0 
		then
			-- if account doesnt exist ...
			if 	exists_account( l_long_name )
			then
				-- set parent guid for next iteration
				if l_count < l_account_count
				then
					set l_parent_guid = get_account_guid(l_long_name);
				end if;
			else
				-- set defaults based on parent
				set l_account_type =   ifnull(p_account_type,   get_account_type(l_parent_guid));
				set l_commodity_guid = ifnull(p_commodity_guid, get_account_commodity(l_parent_guid));
				set l_guid = new_guid();

				-- if we are not at the end of the account name, this is assumed to be a placeholder account
				if l_count < l_account_count
				then
					set l_placeholder = 1;
				else
					set l_placeholder = 0;
				end if;

				-- if the commodity is a currency, assume its in 100 parts otherwise just one part
				if is_currency(l_commodity_guid)
				then
					set l_commodity_scu = 100;
				else
					set l_commodity_scu = 1;
				end if;
				
				if gnc_lock('accounts') then

					insert into accounts (
						guid,
						name,
						account_type,
						commodity_guid,
						commodity_scu,
						non_std_scu,
						parent_guid,
						code,
						description,
						hidden,
						placeholder
					) values (
						l_guid,
						l_short_name,
						l_account_type,
						l_commodity_guid,
						l_commodity_scu,
						0,
						l_parent_guid,
						'',
						'Created by customgnucash.create_account',
						0,
						l_placeholder
					);

					-- log action
					call log( concat('INFORMATION : Added new account ', l_guid, ' "', l_long_name ,'"'));

					call gnc_unlock('accounts');
				end if;

				-- set parent guid for next iteration
				if l_count < l_account_count
				then
					set l_parent_guid = l_guid;
				end if;

			end if; -- if exists_account( l_long_name )

		end if; -- if l_short_name is not null

		set l_count = l_count + 1;

	end while;

	-- call log('DEBUG : END post_account');

	return l_guid;
end;		
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] calculates (and adds splits, if required) for realised capital gains for specified account
-- uses HMRC rules regarding capital gains calculations; when shares are indistinguishable, earlier bought shares are presumed to be sold first
-- does nothing if a (sale) transaction already has a capital gain posted (even if its wrong - so a manual entry made through the GnuCash client is not overwritten by this automatic one)
-- only affects accounts of ASSET or STOCK type
-- manages stock splits (consolidations) if splits are added to GnuCash through the splits tool (which flags them with 'Split' in the action field)
-- doesn't manage accounts without a unit price; (like some mutual or pension funds, or real estate) 
drop function if exists post_gain;
//
create function post_gain
	(
		p_guid				varchar(32)
	)			
	returns varchar(32)
begin
	declare l_realised_gain 		decimal(20,6) default 0;
	declare l_capital_gains_guid		varchar(32);
	declare l_stock_split_ratio		decimal(20,6);
	declare l_capital_gains_account_name	varchar(2048);
	declare l_guid				varchar(32);

	-- variables for holding stock cursor output
	declare l_transaction_guid 		varchar(32);
	declare l_action			varchar(32);
	declare l_post_date 			timestamp;
	declare l_enter_date 			timestamp;
	declare l_total_quantity 		decimal(20,6);
	declare l_total_value 			decimal(20,6);
	declare l_unit_value 			decimal(20,6);
	declare l_transactions_done 		boolean default false;
	declare l_transactions_done_temp 	boolean default false;

	-- outer block cursors
	declare lc_transaction cursor for
		select distinct
			transactions.guid,
			-- convert_tz(transactions.post_date, 'UTC', 'Europe/London'),
			-- convert_tz(transactions.enter_date, 'UTC', 'Europe/London'),
			transactions.post_date,
			transactions.enter_date,
			upper( trim( ',' from group_concat( ifnull(splits.action, '')))),
			sum( 
				 if( 	get_account_type( splits.account_guid ) = 'EXPENSE', 
						0, 
						splits.quantity_num/splits.quantity_denom
					)
				),
			abs( 
				sum( 
					convert_value( 
						splits.value_num/splits.value_denom, 
						transactions.currency_guid, 
						get_default_currency_guid(), 
						transactions.post_date 
						) 
					)
				),
			abs(
				sum( 
					convert_value( 
						splits.value_num/splits.value_denom, 
						transactions.currency_guid, 
						get_default_currency_guid(), 
						transactions.post_date 
						) 
					)
				/
				sum( 
					 if( 	get_account_type( splits.account_guid ) = 'EXPENSE', 
							0, 
							splits.quantity_num/splits.quantity_denom
						)
					)
				)
		from
			transactions
			join splits 
				on transactions.guid = splits.tx_guid
					and splits.tx_guid in (
						select splits.tx_guid 
						from splits 
						where splits.account_guid = p_guid
						)
		where
			splits.quantity_num != 0
			and get_account_type( splits.account_guid ) in ('ASSET', 'STOCK', 'EXPENSE')
		group by 1,2
		order by
			transactions.post_date,
			transactions.enter_date;

	declare continue handler for not found set l_transactions_done =  true;

	-- call log( concat('DEBUG : START post_gain(', ifnull(p_guid, 'null'), ')'));

	-- try to play nicely with other procedures
	-- do is_locked('transactions, splits', 'WAIT');

	-- calculate gains on STOCK or ASSET account types only
	-- ? exclude accounts for which cap gains cannot be calced; accounts denominated in home currency (where there is no independent unit value)
	if get_account_type(p_guid) in ('STOCK', 'ASSET') 
	then
			-- find out where the capital gains are posted for this account
			set l_capital_gains_account_name = get_related_account( p_guid, get_variable('Capital gains account'));
			if exists_account(l_capital_gains_account_name)
			then
				set l_capital_gains_guid = get_account_guid(l_capital_gains_account_name);	
			else
				set l_capital_gains_guid = post_account( l_capital_gains_account_name, null, null);
			end if;

			-- the DB retrieval routines get_account_guid & get_account_attribute set l_transactions_done to true
			set l_transactions_done =  false;

			-- bail if no capital gains account found
			if l_capital_gains_guid is null then
				return null;
			end if;

			-- a temp table to keep a running tally of what's actually in the stock/asset account
			drop temporary table if exists tally;
			create temporary table tally (
				guid			varchar(32),
				post_date 		timestamp default 0,
				enter_date		timestamp default 0,
				quantity 		decimal(20,6),
				unit_value		decimal(20,6)
			);

			open lc_transaction;
			set l_transactions_done = false;

			transaction_loop: loop

				fetch lc_transaction into 
					l_transaction_guid,
					l_post_date,
					l_enter_date,
					l_action,
					l_total_quantity,
					l_total_value,
					l_unit_value;

				if l_transactions_done then 
					leave transaction_loop;
				else
					set  l_transactions_done_temp =  l_transactions_done;
				end if;

				-- when adding stock, add a new row to the running tally
				-- only +ve quantities are ever posted to the tally table
				if l_total_quantity > 0 then

					insert into tally
					values ( l_transaction_guid, l_post_date, l_enter_date, l_total_quantity, l_unit_value );

				-- when selling stock, run through the tally in date order
				else
					
					-- if the reduction in quantity is a 'split' rather than a true sale, the the tally needs to be retrospectively fixed
					if locate('SPLIT', l_action) != 0 then

						--  calculate the split ratio from the quantity immediately before the split
						select (quantity + l_total_quantity) / quantity
						into l_stock_split_ratio
						from tally
						where post_date <  l_post_date
						order by post_date desc
						limit 1;

						-- update portfolio before this date with ratio (quantity goes down, unit value goes up, total value is the same)
						update 	tally
						set 	quantity = quantity * l_stock_split_ratio,
							unit_value = unit_value / l_stock_split_ratio
						where 	post_date <= l_post_date;

					-- non-split sellings needs a totting up of the values in the tally table
					else

						-- remove -ve sign, to aid clear calculations ...
						set l_total_quantity = abs(l_total_quantity);
						
						-- reset realised capital gains to zero for this transactioon
						set l_realised_gain = 0;

						-- need a new block for tally cursor
						tally_block : begin -- tally block

							-- variables for holding stock tally cursor output
							declare l_tally_post_date 		timestamp;
							declare l_tally_enter_date 		timestamp;
							declare l_tally_guid 			varchar(32);
							declare l_tally_quantity 		decimal(20,6);
							declare l_tally_unit_value 		decimal(20,6);
							declare l_stock_tally_done 		boolean default false;
							declare l_stock_tally_done_temp		boolean default false;

							declare lc_stock_tally cursor for
								select distinct
									guid,
									post_date,
									enter_date,
									quantity,
									unit_value
								from tally 
								order by post_date, enter_date;
							declare continue handler for not found set l_stock_tally_done =  true;
										
							open lc_stock_tally;
							set l_stock_tally_done = false;

							-- when selling stock, sell the earliest first
							tally_loop : loop

								fetch lc_stock_tally into 
									l_tally_guid,
									l_tally_post_date,
									l_tally_enter_date,
									l_tally_quantity,
									l_tally_unit_value;
								
								-- stop processing if there's no data or the quantity being sold has been entirely processed
								if l_stock_tally_done or l_total_quantity = 0 then 
									leave tally_loop;
								else
									set l_stock_tally_done_temp = l_stock_tally_done;
								end if;

								-- if the quantity being sold is more than the quantity in the tally row, 
								-- zero the tally row and post a capital gain
								if l_total_quantity >= l_tally_quantity then
										
									-- calculate capital gains
									set l_realised_gain = l_realised_gain -- capital gains already posted
												+ 
												(
													(l_tally_quantity * l_unit_value) -- amount sold for
													-
													(l_tally_quantity * l_tally_unit_value) -- amount bought for
												);

									-- delete tally row (as 'used up')
									-- update tally set quantity = 0 where guid = l_tally_guid;
									delete from tally where guid = l_tally_guid;
										
									-- decrease quantity being sold by tally amount
									set l_total_quantity = l_total_quantity -  l_tally_quantity;
									
								-- if the quantity being sold (or left over) is less than the tally row
								-- do a partial calculation (only really applies to ASSET types relating to commodities; STOCKs are usually integers)
								else

									-- calculate capital gains
									set l_realised_gain = l_realised_gain -- capital gains already posted
												+ 
												(
													( l_total_quantity * l_unit_value) -- amount sold for
													-
													( l_total_quantity * l_tally_unit_value) -- amount bought for
												);
			
									-- reduce tally row
									update tally
										set quantity = quantity - l_total_quantity
										where guid = l_tally_guid;

									-- we've 'used up' the amount that was sold
									set l_total_quantity = 0;

								end if; -- if l_total_quantity >= l_tally_quantity

								set l_stock_tally_done = l_stock_tally_done_temp;
														
							end loop; -- tally_loop

							close lc_stock_tally;

							-- only log the capital gains if a capital gains has not already been posted, 
							-- and this transaction is not a share-split (ie share offer or consolidation)
							if not exists_split(l_transaction_guid, l_capital_gains_guid, p_guid) 
								and locate('SPLIT', l_action) = 0 
							then

								set l_guid = post_split( 	
										l_capital_gains_guid, 
										p_guid, 
										round(l_realised_gain,6), 
										l_transaction_guid, 
										l_post_date, 
										concat('Capital ' , if( l_realised_gain < 0, 'loss', 'gain') , ' calculated by customgnucash.post_gain on ', current_date)
									);
								call log( concat('INFORMATION : Posted capital gain ' , round(l_realised_gain,6), ' for account ' , get_account_long_name(p_guid) ));
							end if;

						end; -- tally block					
					end if; -- if locate('SPLIT', l_action) != 0
				end if; -- if l_total_quantity > 0

				-- set  l_transactions_done back to what it was before so that outer loop can continue
				set  l_transactions_done =  l_transactions_done_temp;

			end loop; -- transaction_loop
	
			close lc_transaction;	

			-- log the date up to which gains have been calculated (otherwise they'll be done repeatedly, to no effect but wasting processor power - see post_all_gains)
			call delete_variable(concat('post_gain(', p_guid ,')')); 
			call post_variable( concat('post_gain(', p_guid ,')'), date_format(l_post_date, '%Y-%m-%d %H:%i:%S'));

			-- for debugging only
			-- select * from tally;
	
	end if; -- if get_account_type(p_guid) in ...

	-- call log('DEBUG : END post_gain');

	return l_guid;

end; -- outer block
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [RW] calculates (and adds) realised capital gains for *all* applicable asset accounts
-- specifically excludes accounts denominated in the default currency (which is *not* the same thing as the account commodity currency); gains can only be calculated on acounts denominated in units (eg stock, currency) the value of which can change wrt default currency
drop procedure if exists post_all_gains;
//
create procedure post_all_gains ()
procedure_block : begin
	declare	l_guid				varchar(32);
	declare l_asset_account_done 		boolean default false;
	declare l_asset_account_done_temp 	boolean default false;

	declare lc_asset_account cursor for
		select distinct guid
		from account_map
		where
			root_guid = get_account_guid('ASSETS')
			and get_account_type(guid) in ('ASSET', 'STOCK')
			and not is_placeholder(guid)
			and get_account_commodity(guid) != get_default_currency_guid()
			-- only deal with last months transactions (as a safety feature)
			and get_transaction_date(guid, 'LATEST', 'POST') > date_add(current_date, interval -1 month)
			-- only if there are fewer units in acct now than day after gains were calced...
			and 	get_account_units(guid, null, date_add(get_transaction_date(guid, 'LATEST', 'POST'), interval -1 day ))
				> 
				get_account_units(guid, null,  get_transaction_date(guid, 'LATEST', 'POST'))
			-- and only for gains not already calced
			and (	get_variable(concat('post_gain(', guid ,')')) is NULL
				or
				str_to_date(get_variable(concat('post_gain(', guid ,')')), '%Y-%m-%d %H:%i:%S') < get_transaction_date(guid, 'LATEST', 'POST')
				);
			-- and get_account_units(guid, null, date_add(str_to_date(get_variable(concat('post_gain(', guid ,')')), '%Y-%m-%d %H:%i:%S'), interval 1 day)) > get_account_units(guid, null, null);
/*			and exists_transaction(
				guid, 
				get_account_guid(get_related_account(guid, 'CASH')),
				ifnull(
					str_to_date(get_variable(concat('post_gain(', guid ,')')), '%Y-%m-%d %H:%i:%S'),
					date_add(current_date, interval -10 year)
				),
				current_date
				);
*/			-- and get_account_attribute(guid, 'ASSET CLASS') not in ('MUTUAL FUND', 'PROPERTY')
	declare continue handler for not found set l_asset_account_done =  true;

	-- call log('DEBUG : START post_all_gains');

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	open lc_asset_account;	
	set l_asset_account_done = false;
	
	asset_account_loop : loop
	
		fetch lc_asset_account into l_guid;
	
		if l_asset_account_done then 
			leave asset_account_loop;
		else
			set l_asset_account_done_temp = l_asset_account_done;
		end if;
		
		do post_gain(l_guid);

		set l_asset_account_done = l_asset_account_done_temp;

	end loop;

	close lc_asset_account;	

	-- call log('DEBUG : END post_all_gains');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [RW] posts dividends for a given account
-- creates dividend income accounts if required (configurable : get_variable('Dividends account') )
-- input dividend value (p_value) is the *per-share* dividend usually found in quotes, not the *total* dividend value (per-share div * no of shares) you actually receive
-- The date of the dividend payment is guessed (but configurable : get_variable('Dividend payment date') ).
-- The value is also guessed, esp if the currency the share price is quoted in is different from that of the dividend, 
-- or the number of shares held the day *before* the dividend date provided is not the correct assumption
-- or a given account gets more than one dividend payment every month
drop function if exists post_dividend;
//
create function post_dividend
	(
		p_guid		varchar(32), 	-- account to add dividend
		p_value		decimal(20,6), 	-- per-share dividend value
		p_date		timestamp
	)
	returns varchar(32)
begin
	declare	l_dividend_account_name		varchar(2048);
	declare l_dividend_account_guid		varchar(32);
	declare l_cash_account_name		varchar(2048);
	declare l_cash_account_guid		varchar(32);
	declare l_transaction_guid		varchar(32);
	declare l_dividend_payment_date		timestamp;
	declare l_dividend_currency		varchar(32);
	declare l_guid				varchar(32);

	-- call log( concat('DEBUG : START post_dividend(', ifnull(p_guid, 'null'), ',', ifnull(p_value, 'null'), ',', ifnull(p_date, 'null'), ')' ));

	-- try to play nicely with other procedures
	-- do is_locked('transactions, splits', 'WAIT');

	set p_date = round_timestamp( ifnull(p_date, current_date) );
	set l_dividend_payment_date = date_add(p_date, interval get_variable('Dividend payment date') day); -- dividends are usually paid 1-4 weeks after the date of the Yahoo finance record 
	set p_value = ifnull(p_value, 0);
	set l_dividend_currency = ifnull( get_commodity_guid( 
						get_variable( concat( get_commodity_mnemonic( get_account_commodity( p_guid) ), ' alternative currency' ) ) 
						), 
					get_account_currency(p_guid)
					);

	if 	exists_account( p_guid )
		and p_value > 0
		and l_dividend_payment_date <= date_add(current_date, interval 3 month) -- can log dividends upto 3 months in advance
	then

		-- get dividends income account (and create it if its not there)
		set l_dividend_account_name = get_related_account( p_guid, get_variable('Dividends account'));
		if exists_account( l_dividend_account_name)
		then
			set l_dividend_account_guid = get_account_guid( l_dividend_account_name );
		else
			set l_dividend_account_guid = post_account( l_dividend_account_name, null, null);	
		end if;	

		-- get related cash account (and create it if its not there)
		set l_cash_account_name = get_related_account( p_guid, 'CASH');
		if exists_account( l_cash_account_name)
		then
			set l_cash_account_guid = get_account_guid( l_cash_account_name );
		else
			set l_cash_account_guid = post_account( l_cash_account_name, null, null);
		end if;	
		
		-- get actual value of dividends received (per-share value * number of shares [on previous day] ) converted into whatever currency your cash account uses
		-- it is not always clear what currency Yahoo Finance uses to denominate per-share dividends (Yahoo finance data actually lies about it, and mixes GBP with USD with no indication - see EMDV.L), so it can be overidden : SQL> put_variable('EMDV.L alternative currency', 'USD');
		set p_value = convert_value(
				p_value * get_account_units(p_guid, null, date_add(p_date, interval -1 day)),
				l_dividend_currency, 
				get_account_commodity(l_cash_account_guid),
				l_dividend_payment_date
				);
	
		-- if we have all required data, and a dividend payment hasnt been recorded 30 days either way, then insert dividends into DB 
		if 	l_dividend_account_guid is not null
			and l_cash_account_guid is not null
			and ifnull(p_value, 0) > 0
			and not exists_transaction(	p_guid,
							l_dividend_account_guid, 
							date_add( l_dividend_payment_date, interval -30 day), 
							date_add( l_dividend_payment_date, interval 30 day)
						)
		then
			-- record transfer from dividend income account to stock account
			set l_guid = post_split( 
						l_dividend_account_guid, 
						p_guid, 
						p_value, 
						null, 
						l_dividend_payment_date, 
						concat('Added by customgnucash.post_dividends on ', current_date )
					);

			-- record transfer from stock account to cash account
			set l_guid = post_split( 
						p_guid, 
						l_cash_account_guid,
						p_value, 
						l_guid, -- add this split to the transaction created above
						l_dividend_payment_date, 
						concat('Added by customgnucash.post_dividends on ', current_date )
					);

			call log( concat(	'INFORMATION : Added dividend of ', 
						get_commodity_mnemonic(l_dividend_currency), 
						p_value, 
						' on ', 
						l_dividend_payment_date, 
						' to account ',
						get_account_long_name(p_guid) 
				));

		end if; -- if 	l_dividend_account_guid is not null

	end if;

	-- call log('DEBUG : END post_dividend');
	
	return l_guid;
end;
//
set @function_count = ifnull(@function_count,0) + 1;
//

-- [G] REPORTS

-- [R] Bundles up logs in the log table and prepares a report about them for the user
drop procedure if exists report_anomalies;
//
create procedure report_anomalies()
procedure_block:begin
	declare	l_current_timestamp	timestamp default current_timestamp;
	declare l_report		text;
	-- declare l_report_header		varchar(500);
	declare	l_anomaly_done 		boolean default false;
	declare	l_anomaly_done_temp	boolean default false;
	declare l_error_level		varchar(20);
	declare	l_class			varchar(20);
	declare l_log			varchar(1000);
	declare l_count			integer;
	declare l_date			timestamp;
	declare l_logdate		timestamp;

	declare lc_anomaly cursor for
		select 	substring_index(log, ' ', 1),
			log,
			count(*),
			min(logdate)
		from 	log
		where 	( 	substring_index(log, ' ', 1) = 'ERROR' 
				or substring_index(log, ' ', 1) = 'WARNING' 
				or substring_index(log, ' ', 1) = 'INFORMATION'
			)
		and	logdate > l_date
		group by substring_index(log, ' ', 1), log
		order by min(logdate);			
	declare continue handler for not found set l_anomaly_done = true;

	-- call log('DEBUG : START report_anomalies');

	-- try to play nicely with other procedures
	do is_locked('log', 'WAIT');

	set l_date = ifnull(str_to_date(get_variable('Anomalies reported'), '%Y-%m-%d %H:%i:%s'), date_add(l_current_timestamp, interval -1 year));
	set l_error_level = upper(ifnull(get_variable('Error level'), 'ERROR'));

	open lc_anomaly;	
	set l_anomaly_done = false;
	
	-- loop over each anomaly returned by the cursor
	anomaly_loop : loop
		
		fetch lc_anomaly into l_class, l_log, l_count, l_logdate;
	
		if l_anomaly_done then 
			leave anomaly_loop;
		else
			set l_anomaly_done_temp = l_anomaly_done;
		end if;

		-- report log message if class and error level match up
		if 	(l_error_level = 'ERROR' and l_class = 'ERROR')
			or
			(l_error_level = 'WARNING' and (l_class = 'ERROR' or l_class = 'WARNING' ))
			or
			(l_error_level = 'INFORMATION' and (l_class = 'ERROR' or l_class = 'WARNING' or l_class = 'INFORMATION' ))
		then
			call write_report(	l_report,
						concat(	l_class, '|', l_count, '|', date_format(l_logdate, '%Y-%m-%d %H:%i:%s'), '|', replace(l_log, concat(l_class, ' : '), '' )),
						'table-middle');
		end if;

		set l_anomaly_done = l_anomaly_done_temp;

	end loop;

	close lc_anomaly;	

	if l_report is not null then
		
		call write_report(	l_report,
					'Class|Count|First date|Log',
					'table-start');

		-- set l_report = concat(l_report_header, l_report);

		call write_report(	l_report,
					null,
					'table-end');

		-- stick on subject line
		call write_report(	l_report, 
					concat('Anomalies reported since ', convert(l_date, char)), 
					'title');

		-- delete any previously stored version of this report (which are now out-of-date)
		call delete_series('report_anomalies', null); 

		-- write completed report to variables table
		call post_variable('report_anomalies', l_report);

		-- log the latest date anomalies have been checked for
		call delete_variable('Anomalies reported');
		call post_variable('Anomalies reported', date_format(l_current_timestamp, '%Y-%m-%d %H:%i:%s'));

	end if; -- if l_report is not null

	-- call log('DEBUG : END report_anomalies');

end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] Returns a table itemising capital gains, dividends and interest returns 
-- in default currency, as absolute %, as % pa
-- may take a v long time if you have many accounts to process
drop procedure if exists report_account_gains;
//
create procedure report_account_gains
	(
		p_guid				varchar(32),
		p_date1				timestamp,
		p_date2				timestamp
	)
procedure_block : begin
	declare	l_guid				varchar(32);
	declare	l_account_name			varchar(2048);
	declare	l_account_type			varchar(2048);
	declare	l_account_value 		decimal(20,6);

	-- variables for holding account costs
	declare	l_remainder_cost		decimal(20,6);
	declare	l_sold_cost			decimal(20,6);
	declare	l_average_cost			decimal(20,6);

	-- variables for holding account gains
	declare l_capital_gains 		decimal(20,6);
	declare l_unrealised_gains 		decimal(20,6);
	declare	l_dividends			decimal(20,6);
	declare	l_interest			decimal(20,6);

	-- variables for keeping track of dates
	declare l_date				timestamp;
	declare	l_earliest_transaction_date	timestamp;
	declare l_latest_transaction_date	timestamp;
	declare	l_v_earliest_transaction_date	timestamp;
	declare l_v_latest_transaction_date	timestamp;
	declare	l_years				decimal(20,6);
	
	-- variables for holding aggregated values
	declare	l_total_remainder_cost		decimal(20,6) default 0;
	declare	l_total_sold_cost		decimal(20,6) default 0;
	declare	l_total_average_cash_cost	decimal(20,6) default 0;
	declare	l_total_average_asset_cost	decimal(20,6) default 0;
	declare l_total_realised_gains 		decimal(20,6) default 0;
	declare l_total_unrealised_gains 	decimal(20,6) default 0;
	declare	l_total_dividends		decimal(20,6) default 0;
	declare	l_total_interest		decimal(20,6) default 0;
	declare	l_total_years			decimal(20,6) default 0;

	-- variables for holding report output
	declare l_report			text;
	declare l_asset_report			text;
	declare l_bank_report			text;
	-- declare l_report_header			varchar(500);

	-- variables for managing cursors
	declare l_asset_account_done 		boolean default false;
	declare l_asset_account_done_temp 	boolean default false;
	declare lc_asset_account cursor for
		select distinct guid
		from 	account_map
		where
			root_guid = get_account_guid('ASSETS') -- account is mandatorily an ASSET
			and not is_placeholder(guid) -- and is not just used as a placeholder
			and is_used(guid) -- and has transactions in it
			and (
				p_guid = root_guid
				or is_child_of(guid, p_guid, true) -- ie, only perform query on ASSETS subset if p_guid is not ASSETS
			    )
			and  (	( get_account_type(guid) in ('ASSET', 'STOCK')
				  and get_account_commodity(guid) != get_default_currency_guid() ) -- and is non-cash ASSET/STOCK which isn't the default currency entry
				  or
				  get_account_type(guid) in ('BANK', 'CASH') -- or is a BANK/CASH asset in any currency
			     )
		order by
			long_name;			
	declare continue handler for not found set l_asset_account_done =  true;

	-- call log( concat('DEBUG : START report_account_gains(', ifnull(p_guid, 'null'), ',', ifnull(p_date1, 'null'), ',', ifnull(p_date2, 'null'), ')'));
	
	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  	get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
		or get_variable('Customgnucash status') != 'OK'
	then
		call log( concat('WARNING : Report declined to start'));
		leave procedure_block;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts, transactions, splits', 'WAIT');

	-- set default dates (strip off timestamps from date)
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions
		where	post_date <= current_timestamp;
	end if;
	set p_date1 = round_timestamp(ifnull(p_date1, current_timestamp));

	-- the latest date considered should not be in the future
/*	if p_date2 is null then
		select 	max(post_date)
		into 	p_date2
		from 	transactions
		where	post_date <= current_timestamp;
	end if;
*/
	set p_date2 = round_timestamp(ifnull(p_date2, current_timestamp));

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- set default account ID to work from (the root ASSET account)
	set p_guid = ifnull(p_guid, get_account_guid('ASSETS'));

	-- dont run this report again if the output still exists
	-- ideally, this should check for min date of transactions for account -> max date thereof, but these are only calced later 
	if not exists_variable( concat('report_account_gains(' , p_guid , ',' , p_date1 , ',' , p_date2 , ')'))  then

		-- call log('DEBUG : START open lc_asset_account');

		open lc_asset_account;	
		set l_asset_account_done = false;

		-- call log('DEBUG : END open lc_asset_account');
	
		-- loop over each account returned by the cursort
		asset_account_loop : loop
		
			fetch lc_asset_account into l_guid;
	
			if l_asset_account_done then 
				leave asset_account_loop;
			else
				set l_asset_account_done_temp = l_asset_account_done;
			end if;

			-- call log( concat('DEBUG : l_guid=', ifnull(l_guid, 'null') ));

			-- check p_date2 is not later than latest transaction in account 
			set l_latest_transaction_date =  least(p_date2, get_transaction_date(l_guid, 'LATEST', 'POST'));

/*			select 	min(dates.date)
			into 	l_latest_transaction_date
			from
			(
				select  max(post_date) as date
				from 	transactions
					join splits
						on transactions.guid = splits.tx_guid
				where	splits.account_guid = l_guid
				and 	post_date <= current_timestamp
				union
				select 	p_date2
			) dates;
*/
			-- call log( concat('DEBUG : l_latest_transaction_date=', ifnull(l_latest_transaction_date, 'null') ));

			-- check p_date1 is not earlier than earliest transaction in account 
			set l_earliest_transaction_date =  greatest(p_date1, get_transaction_date(l_guid, 'EARLIEST', 'POST'));

/*			select 	max(dates.date)
			into 	l_earliest_transaction_date
			from
			(
				select  min(post_date) as date
				from 	transactions
					join splits
						on transactions.guid = splits.tx_guid
				where	splits.account_guid = l_guid
				and 	post_date <= p_date2
				union
				select 	p_date1
			) dates;
*/
			-- call log( concat('DEBUG : l_earliest_transaction_date=', ifnull(l_earliest_transaction_date, 'null') ));

			-- keep a track of the absolutely earliest and latest transaction date for all accounts being reported
			if 	l_earliest_transaction_date < l_v_earliest_transaction_date 
				or l_v_earliest_transaction_date is  null
			then
				set l_v_earliest_transaction_date = l_earliest_transaction_date;
			end if;

			if 	l_latest_transaction_date > l_v_latest_transaction_date 
				or l_v_latest_transaction_date is  null
			then
				set l_v_latest_transaction_date = l_latest_transaction_date;
			end if;

			-- clear values from last loop
			set l_capital_gains = null;
			set l_account_value = null;
			set l_unrealised_gains = null;
			set l_dividends = null;
			set l_interest = null;

			-- get account value for current timestamp 
			set l_account_value = get_account_value(	l_guid, 
									get_default_currency_guid(),
									l_earliest_transaction_date, 
									p_date2,
									false);

			-- call log( concat('DEBUG : l_account_value=', ifnull(l_account_value, 'null') ));

			-- get specialised cost values		
			call get_account_costs(	l_guid, 
						l_earliest_transaction_date, 
						l_latest_transaction_date, 
						l_remainder_cost, 
						l_sold_cost, 
						l_average_cost);

			-- set and standardise account name 
			set l_account_name = get_account_long_name(l_guid);
			set l_account_name = replace(replace(l_account_name,  concat( substring_index( l_account_name, ':', 2), ':'), ''), ':', ':<br>');

			-- call log( concat('DEBUG : l_account_name=', ifnull(l_account_name, 'null') ));

			-- set and standardise account types (CASH and BANK are treated the same way, etc)
			set l_account_type = get_account_type(l_guid);

			-- call log( concat('DEBUG : l_account_type=', ifnull(l_account_type, 'null') ));

			set l_years = timestampdiff(DAY, l_earliest_transaction_date, if( ifnull(l_account_value,0) = 0, l_latest_transaction_date, p_date2 ) ) / 365.25;

			-- call log( concat('DEBUG : l_years=', ifnull(l_years, 'null') ));

			-- add values to report table
			if l_account_type in ('ASSET', 'STOCK') then

				-- call log('DEBUG : l_account_type in ASSET, STOCK');

				set l_capital_gains = get_transactions_value(	l_guid, 
										-- get_account_guid( get_variable('Capital gains account')),
										get_account_guid(get_related_account(l_guid, get_variable('Capital gains account'))),
										null, 
										l_earliest_transaction_date, 
										l_latest_transaction_date,
										false);

				-- call log( concat('DEBUG : l_capital_gains=', ifnull(l_capital_gains, 'null') ));

				if l_account_value > 0 then
					set l_unrealised_gains = l_account_value - l_remainder_cost;
				else
					set l_unrealised_gains = 0;
				end if;

				if l_account_type = 'STOCK' then

					-- call log('DEBUG : l_account_type in STOCK');

					set l_dividends = get_transactions_value(	l_guid, 
											-- get_account_guid( get_variable('Dividends account')),
											get_account_guid(get_related_account(l_guid, get_variable('Dividends account'))),
											null, 
											l_earliest_transaction_date, 
											l_latest_transaction_date, 
											false);

					-- call log( concat('DEBUG : l_dividends=', ifnull(l_dividends, 'null') ));		
				end if;

				-- keep running total of aggregates
				set l_total_realised_gains 	= ifnull(l_total_realised_gains, 0) 	+ ifnull(l_capital_gains,0);
				set l_total_unrealised_gains 	= ifnull(l_total_unrealised_gains, 0) 	+ ifnull(l_unrealised_gains,0);
				set l_total_dividends 		= ifnull(l_total_dividends, 0) 		+ ifnull(l_dividends,0);
				set l_total_sold_cost 		= ifnull(l_total_sold_cost, 0) 		+ ifnull(l_sold_cost,0);
				set l_total_remainder_cost 	= ifnull(l_total_remainder_cost, 0) 	+ ifnull(l_remainder_cost,0);
				set l_total_average_asset_cost 	= ifnull(l_total_average_asset_cost, 0) + ifnull(l_average_cost,0);

				if ifnull(l_capital_gains,0) != 0
					or ifnull(l_unrealised_gains,0) != 0
					or ifnull(l_dividends,0) != 0
				then
					call write_report(	l_asset_report,
								concat(
									if( 	ifnull(l_account_value,0) = 0,
										concat('<font size=-1><i>', l_account_name, '</i>'),
										l_account_name
									),
									'|',
									prettify( l_capital_gains ),
									'|',
									if(	ifnull( l_sold_cost,0 ) = 0, 
										'&nbsp;', 
										 prettify( (l_capital_gains * 100) / l_sold_cost )
									),
									'|',
									if( 	ifnull( l_years,0 ) = 0 or ifnull( l_sold_cost,0) = 0, 
										'&nbsp;', 
										 prettify( (l_capital_gains * 100) / (l_sold_cost * l_years ) )
									),
									'|',
									prettify( l_unrealised_gains ),
									'|',
									if(	ifnull( l_remainder_cost,0 ) = 0, 
										'&nbsp;', 
										 prettify( (l_unrealised_gains * 100) / l_remainder_cost )
									),
									'|',
									if( 	ifnull( l_years,0 ) = 0 or ifnull( l_remainder_cost,0 ) = 0, 
										'&nbsp;', 
										 prettify( (l_unrealised_gains * 100) / (l_remainder_cost * l_years ) )
									),
									'|',
									prettify( l_dividends ),
									'|',
									if(	ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										 prettify( (l_dividends * 100) / l_average_cost )
									),
									'|',
									if( 	ifnull( l_years,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										 prettify( (l_dividends * 100) / (l_average_cost * l_years ) )
									)							
								),
								'table-middle');

				end if; -- if ifnull(l_capital_gains,0) != 0
		
			elseif l_account_type in ('BANK', 'CASH') then

				-- call log('DEBUG : l_account_type in BANK, CASH');

				set l_interest = get_transactions_value(	
								l_guid, 
								-- get_account_guid( get_variable('Interest account')), 
								get_account_guid(get_related_account(l_guid, get_variable('Interest account'))),
								null, 
								l_earliest_transaction_date, 
								l_latest_transaction_date, 
								false);

				-- call log( concat('DEBUG : l_interest=', ifnull(l_interest, 'null') ));

				-- keep running total of aggregates
				set l_total_interest 		= ifnull(l_total_interest, 0) 		+ ifnull(l_interest,0);
				set l_total_average_cash_cost 	= ifnull(l_total_average_cash_cost, 0) 	+ ifnull(l_average_cost,0);

				if ifnull(l_interest,0) != 0 then

					-- occasional "ERROR 1271 (HY000): Illegal mix of collations for operation 'concat'" occur here
					call write_report(	l_bank_report,
								concat(
									if( 	ifnull(l_account_value,0) = 0,
										concat('<font size=-1><i>', l_account_name, '</i>'),
										l_account_name
									),
									'|',
									prettify( l_interest ),
									'|',
									if(	ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										prettify( (l_interest * 100) / l_average_cost )
									),
									'|',
									if( 	ifnull( l_years,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										prettify( (l_interest * 100) / (l_average_cost * l_years ) 
										)
									)
								),
								'table-middle');

				end if; -- if ifnull(l_interest,0) != 0

			end if;

			set l_asset_account_done = l_asset_account_done_temp;

		end loop;

		close lc_asset_account;	

		-- calculate the *complete* period being calculated, in years
		set l_total_years = timestampdiff(DAY, l_v_earliest_transaction_date, p_date2) / 365.25;

		-- complete asset report
		if l_asset_report is not null then

			-- calculate asset totals
			call write_report(	l_asset_report,
						concat(
							'<b>TOTAL</b>',
							'|',
							prettify( l_total_realised_gains ),
							'|',
							if(	ifnull( l_total_sold_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( (l_total_realised_gains * 100) / l_total_sold_cost )
							),
							'|',
							if( 	ifnull( l_total_years,0 ) = 0 or ifnull( l_total_sold_cost,0) = 0, 
								'&nbsp;',
								prettify( (l_total_realised_gains * 100) 
									/ 
									(l_total_sold_cost * l_total_years) 
								)
							),
							'|',
							prettify( l_total_unrealised_gains ),
							'|',
							if(	ifnull( l_total_remainder_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( (l_total_unrealised_gains * 100) / l_total_remainder_cost )
							),
							'|',
							if( 	ifnull( l_total_years,0 ) = 0 or ifnull( l_total_remainder_cost,0) = 0, 
								'&nbsp;', 
								prettify( (l_total_unrealised_gains * 100) 
									/ 
									(l_total_remainder_cost * l_total_years ) 
								)
							),
							'|', 
							prettify( l_total_dividends ),
							'|',
							if(	ifnull(l_total_average_asset_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( (l_total_dividends * 100) / l_total_average_asset_cost )
							),
							'|',
							if( 	ifnull( l_total_years,0 ) = 0 or ifnull( l_total_average_asset_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( (l_total_dividends * 100) 
									/ 
									(l_total_average_asset_cost * l_total_years )
								)
							)
						),
						'table-middle');

			-- create stocks table header
			-- set l_report_header = null;
			call write_report(	l_asset_report,
						'Account|Realised gains|Realised gains (% absolute)|Realised gains (% annualised)|Unrealised gains|Unrealised gains (% absolute)|Unrealised gains (% annualised)|Dividends|Dividends (% absolute)|Dividends (% annualised)',
						'table-start');

			-- stick stocks header on in correct place
			-- set l_asset_report = concat(l_report_header, l_asset_report);

			-- complete stocks report
			call write_report(	l_asset_report,
						null,
						'table-end');

			-- stick it on main report
			set l_report =	concat( ifnull(l_report,''),
						'</br>Asset report</br>',
						l_asset_report
					);

		end if;

		-- complete bank report
		if l_bank_report is not null then
			
			-- calculate cash totals
			call write_report(	l_bank_report,
						concat(
							'<b>TOTAL</b>',
							'|',
							prettify(l_total_interest),
							'|',
							if( 	ifnull( l_total_interest,0 ) = 0 or ifnull( l_total_average_cash_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( l_total_interest * 100 / l_total_average_cash_cost )
							),
							'|',
							if( 	ifnull( l_total_interest,0 ) = 0 or ifnull( l_total_average_cash_cost,0 ) = 0, 
								'&nbsp;', 
								prettify( 
									(l_total_interest * 100)
									/ 
									(l_total_average_cash_cost * l_total_years) 
								)
							)
						),
						'table-middle');

			-- create cash table header
			-- set l_report_header = null;
			call write_report(	l_bank_report,
						'Account|Interest|Interest (% absolute)|Interest (% annualised)',
						'table-start');

			-- stick cash header on in correct place
			-- set l_bank_report = concat(l_report_header, l_bank_report);

			-- complete cash report
			call write_report(	l_bank_report,
						null,
						'table-end');

			-- stick it on main report
			set l_report =	concat( ifnull(l_report,''),
						'</br>Cash report</br>',
						l_bank_report
					);
		end if;

		-- assemble final complete report and store in variables table
		if l_report is not null then
			
			-- stick on subject line
			call write_report(	l_report, 
						'Account gains report.', 
						'title');

			-- delete any previously stored version of this report (which are now out-of-date)
			call delete_series('report_account_gains', concat('1=', p_guid)); 

			-- write completed report to variables table
			call post_variable( concat('report_account_gains(' , p_guid , ',' , p_date1 , ',' , p_date2 , ')') , l_report);

		end if; -- if l_report is not null


	end if; -- if not exists_variable( concat('report_account_gains(' , p_guid , ',' , p_date1 , ',' , p_date2 , ')')) 

	-- call log('DEBUG : END report_account_gains');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] returns how much remains in your ISA allowance this tax year (only)
-- only applicable in the UK
drop procedure if exists report_remaining_isa_allowance;
//
create procedure report_remaining_isa_allowance
	(
		in 	p_date			timestamp
	)
procedure_block:begin
	declare	l_report 			text;
	declare l_isa_contribution 		decimal(20,6) default 0;
	declare l_cash_accounts 		text; -- varchar(60000);
	declare l_ISA_accounts 			text; -- varchar(60000);
	declare l_tax_year_start 		timestamp;
	declare l_tax_year_end 			timestamp;
	declare l_cash_account_counter 		smallint default 1;
	declare l_ISA_account_counter 		smallint default 1;
	declare l_ISA_allowance_remaining	decimal(8,2);
	
	-- call log( concat('DEBUG : START report_remaining_isa_allowance(', ifnull(p_date, 'null'), ')' ));

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  	get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
		or get_variable('CustomGnucash status') != 'OK'
		or get_variable('Jurisdiction') != 'UK'
	then
		call log( concat('WARNING : Report declined to start.') );
		leave procedure_block;
	end if;

	-- standardise date
	set p_date = from_days( to_days( ifnull(p_date, current_timestamp) ));
	
	-- dont run this report again if the output still exists
	if not exists_variable( concat('report_remaining_isa_allowance(' , p_date , ')')) then

		-- set tax year (within which ISAs run)
		set l_tax_year_start = get_tax_year_end(-1);
		set l_tax_year_end = get_tax_year_end(0);

		-- determine cash accounts whence ISA contributions are made
		set l_cash_accounts = get_account_children( get_account_guid( get_variable( 'Cash account' )), true);

		-- determine ISA accounts whither ISA contributions are sent
		set l_ISA_accounts = concat(
						get_account_children( get_account_guid( get_variable( 'Cash ISA account' )), true),
						',', 
						get_account_children( get_account_guid( get_variable( 'Stocks ISA account' )), true) 
					);

		-- wind through each combination of ISA source and sink accounts
		while l_ISA_account_counter <=  get_element_count( l_ISA_accounts, ',' ) do

			set l_cash_account_counter = 1;

			while l_cash_account_counter <= get_element_count( l_cash_accounts, ',') do

				set l_isa_contribution = l_isa_contribution 
							+
							get_transactions_value(
								get_element( l_ISA_accounts, l_ISA_account_counter, ',' ),
								get_element( l_cash_accounts, l_cash_account_counter, ',' ),
								null,
								l_tax_year_start,
								l_tax_year_end,
								false
							);

				set l_cash_account_counter = l_cash_account_counter + 1;

			end while;

			set l_ISA_account_counter = l_ISA_account_counter + 1;

		end while;
		
		set l_ISA_allowance_remaining = round( get_variable( concat('ISA allowance ', date_format(l_tax_year_end, '%Y') ) ) - l_isa_contribution , 2);

		-- compile report
		if 	l_ISA_allowance_remaining is not null 
			and l_ISA_allowance_remaining > 0 
		then
			call write_report(	l_report, 'ISA allowance report', 'title');
			call write_report(	l_report,
							concat(	'Your remaining ISA allowance of GBP', 
									 prettify(l_ISA_allowance_remaining), 
									' must be used by ', 
									date_format(get_tax_year_end(0), '%d %M %Y'),
									'.'
									),
							'plain'
							);

			-- delete previous iterations of report (only the latest is relevant)
			call delete_series('report_remaining_isa_allowance', null);

			-- write report to variables table
			call post_variable( concat('report_remaining_isa_allowance(' , p_date , ')') , l_report);

		end if; -- if 	l_ISA_allowance_remaining is not null 
	
	end if; -- if not exists_variable

	-- call log('DEBUG : END report_remaining_isa_allowance');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] Breaks down allocation of given account by asset class or location
-- relies entirely on user-defined account attributes such as [asset class=<asset class>], [location=<location>]
drop procedure if exists report_asset_allocation;
//
create procedure report_asset_allocation
	(
		p_guid				varchar(32),
		p_variable			varchar(2048), -- concatenate variables with a comma
		p_date				timestamp
	)
procedure_block : begin
	declare l_total 			decimal(15,2);
	declare l_classification		varchar(50);
	declare l_value				decimal(15,2);
	declare l_proportion			decimal(15,2);
	declare l_report			text;
	-- declare l_report_header			varchar(500);

	declare l_account_list_done 		boolean default false;
	declare l_account_list_done_temp 	boolean default false;

	declare lc_account_list cursor for
		select
			ifnull(
				case upper(p_variable)
					when 'TYPE' 		then 
						get_account_type(account_map.guid)
					when 'ASSET CLASS' 	then
						ifnull(
							get_account_attribute(account_map.guid,'Asset class'), 
							if( get_account_type(account_map.guid) = 'BANK', -- mush 'BANK' and 'CASH' types together
								'CASH', 
								get_account_type(account_map.guid)
							)
						)
					else
						case get_element_count( p_variable, ':')
							when 1 then get_account_attribute(account_map.guid, p_variable)
							when 2 then
								concat(	get_account_attribute(account_map.guid,  get_element(p_variable, 1, ':') ), 
									' ', 
									get_account_attribute(account_map.guid,  get_element(p_variable, 2, ':') )
								)
							when 3 then
								concat(	get_account_attribute(account_map.guid,  get_element(p_variable, 1, ':') ), 
									' ', 
									get_account_attribute(account_map.guid,  get_element(p_variable, 2, ':') ),
									' ', 
									get_account_attribute(account_map.guid,  get_element(p_variable, 3, ':') )
								)

						end
							
				end,
				'UNKNOWN'
			),
			sum(
				get_account_value(
					account_map.guid, 
					get_default_currency_guid(), 
					null,
					p_date, 
					false)
			)
		from
			account_map
		where
			root_guid = p_guid
			and not is_placeholder(account_map.guid)
		group by 1
		having sum(
				get_account_value(
					account_map.guid, 
					get_default_currency_guid(), 
					null,
					p_date, 
					false)
			) != 0
		order by 2 desc;
	declare continue handler for not found set l_account_list_done =  true;

	-- call log( concat( 'DEBUG : START report_asset_allocation(', ifnull(p_guid, 'null'), ',', ifnull(p_variable, 'null'), ',', ifnull(p_date, 'null'), ')'));

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  	get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
		or get_variable('Customgnucash status') != 'OK'
	then
		call log( concat('WARNING : Report declined to start' ));
		leave procedure_block;
	end if;

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');
	
	set p_guid = ifnull(p_guid, get_account_guid('Assets'));
	set p_variable = ifnull(p_variable, 'TYPE');
	set p_date = round_timestamp(ifnull(p_date, current_timestamp));
	set l_total = get_account_value( p_guid, get_default_currency_guid(), null, p_date, true);

	-- loop through each account to be assessed
	open lc_account_list;	
	set l_account_list_done = false;

	account_list_loop : loop

		fetch lc_account_list 
		into l_classification, l_value;

		if l_account_list_done then 
			leave account_list_loop;
		else
			set l_account_list_done_temp = l_account_list_done;
		end if;

		set l_proportion = l_value * 100 / l_total;

		call write_report(	l_report,
					concat(
						l_classification,
						'|',
						prettify(l_value),
						'|',
						prettify(l_proportion),
						'|',
						html_bar(
							l_proportion,
							case
								when l_proportion > 80 then 'red'
								when l_proportion > 50 then 'orange'
								when l_proportion > 20 then 'blue'
								else 'green'
							end
						)
					),
					'table-middle');

		set l_account_list_done = l_account_list_done_temp;

	end loop;

	if l_report is not null then

		-- create table header
		call write_report(	l_report,
					concat(
						'Classification|',
						get_constant('Default currency'),
						'|Allocation (%)|Allocation (graphical)'
						),
					'table-start');

		-- stick header on in correct place
		-- set l_report = concat(l_report_header, l_report);

		-- add in total line
		call write_report(	l_report,
					concat(
						'<b>TOTAL</b>|',
						prettify(l_total),
						'|100.00|',
						html_bar(100, 'gray')
						),
					'table-middle');

		-- complete report
		call write_report(	l_report,
					null,
					'table-end');

		-- stick on subject line
		call write_report(	l_report,
					concat(	'Asset allocation report, by ',
						p_variable
						), 
					'title');

		-- delete previous iterations of report (only the latest is relevant)
		call delete_series('report_asset_allocation', concat('1=', p_guid , ',2=', p_variable));

		-- write completed report to variables table
		call post_variable( concat('report_asset_allocation(' , p_guid , ',' , p_variable , ',' , p_date , ')') , l_report);

	end if;

	-- call log('DEBUG : END report_asset_allocation');

end; -- report_asset_allocation
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] calculates *UK* capital gains, income and inheritance tax for specified year (default latest completed tax year)
-- all amounts in GBP
-- based on UK HMRC rules July 2014
-- only applies to persons aged under 65 (there's a whole raft of other rules for them!)
-- incomplete
drop procedure if exists report_uk_tax;
//
create procedure report_uk_tax
	(
		p_index	int
	)
procedure_block : begin
	declare l_report_name 			varchar(700);
	declare l_report 			text;
	declare l_tax_year_start 		timestamp;
	declare l_tax_year_end 			timestamp;

	declare l_taxable_taxed_salary 		decimal(20,6);
	declare l_taxable_untaxed_salary 	decimal(20,6);
	declare l_taxable_taxed_interest 	decimal(20,6);
	declare l_taxable_untaxed_interest	decimal(20,6);
	declare l_taxable_dividends 		decimal(20,6);
	declare l_taxable_capital_gains 	decimal(20,6);
	declare l_inheritance 			decimal(20,6);
	declare l_gross_income 			decimal(20,6);
	declare l_gross_salary 			decimal(20,6);
	declare l_gross_savings 		decimal(20,6);
	declare l_total_tax_paid 		decimal(20,6);

	declare l_interest_income_tax_paid 	decimal(20,6);
	declare l_dividends_income_tax_paid	decimal(20,6);
	declare l_salary_income_tax_paid 	decimal(20,6);
	-- declare l_national_insurance_paid 	decimal(20,6);
	declare l_capital_gains_tax_paid 	decimal(20,6);
	declare l_tax_rebates 			decimal(20,6);
	declare l_self_assessment_tax_paid 	decimal(20,6);
	declare l_inheritance_tax_paid 		decimal(20,6);
	declare l_personal_allowance 		decimal(20,6);

	declare l_income_tax_calculated 	decimal(20,6) default 0;
	-- declare l_national_insurance_calculated decimal(20,6) default 0;
	declare l_capital_gains_tax_calculated 	decimal(20,6) default 0;
	declare l_inheritance_tax_calculated 	decimal(20,6) default 0;

	-- call log( concat('DEBUG : START report_uk_tax(', ifnull(p_index, 'null'), ')' ));

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  	get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
		or get_variable('CustomGnucash status') != 'OK'
		or get_variable('Jurisdiction') != 'UK'
	then
		call log( concat('WARNING : Report declined to start.') );
		leave procedure_block;
	end if;

	-- try to play nicely with other procedures
	do is_locked('transactions, accounts', 'WAIT');

	-- set defaults (if null, assume tax report required for latest completed tax year)
	set p_index = ifnull(p_index, -1);

	-- set tax dates
	set l_tax_year_start = get_tax_year_end(p_index - 1);
	set l_tax_year_end = get_tax_year_end(p_index);

	-- get values for self-assessment report
	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_taxed_salary
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Salary account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+TAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_untaxed_salary
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Salary account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+UNTAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_taxed_interest
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Interest account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+TAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_untaxed_interest
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Interest account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+UNTAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_dividends
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Dividends account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+UNTAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_taxable_capital_gains
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Capital gains account')), long_name) > 0
		and get_account_attribute(guid, 'Tax state') = 'TAXABLE+UNTAXED';

	select	- round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_inheritance
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Inheritance account')), long_name) > 0;

	select	round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_interest_income_tax_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Income tax (interest) paid account')), long_name) > 0;

	select	round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_salary_income_tax_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Income tax (salary) paid account')), long_name) > 0;

/*
	select	round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_national_insurance_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('National insurance paid account')), long_name) > 0;
*/

	select	round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_tax_rebates
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Income tax rebates account')), long_name) > 0;

	-- the following are paid in the tax year *after* the one being specified
	select	round(sum(get_account_value(guid, get_default_currency_guid(), date_add(l_tax_year_start, interval 1 year), date_add(l_tax_year_end, interval 1 year), false)),2)
	into 	l_capital_gains_tax_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Capital gains tax paid account')), long_name) > 0;

	select	round(sum(get_account_value(guid, get_default_currency_guid(), date_add(l_tax_year_start, interval 1 year), date_add(l_tax_year_end, interval 1 year), false)),2)
	into 	l_self_assessment_tax_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Self assessment tax paid account')), long_name) > 0;

	-- not sure when this one is paid
	select	round(sum(get_account_value(guid, get_default_currency_guid(), l_tax_year_start, l_tax_year_end, false)),2)
	into 	l_inheritance_tax_paid
	from 	account_map 
	where	is_used(guid)
		and locate ( upper(get_variable('Inheritance tax paid account')), long_name) > 0;

	-- Dividend starter rate tax is removed at source and neither seen nor recorded in GnuCash
	set l_dividends_income_tax_paid = round(l_taxable_dividends * get_variable('Income tax starter rate'),2); 

	-- calculate totals
	set l_gross_salary 	= l_taxable_taxed_salary + l_taxable_untaxed_salary;
	set l_gross_savings 	= l_taxable_taxed_interest + l_taxable_untaxed_interest;
	set l_gross_income 	= l_gross_salary 
				+ l_gross_savings 
				+ l_taxable_dividends + l_dividends_income_tax_paid;

	set l_total_tax_paid = 	ifnull(l_interest_income_tax_paid, 0) +
				ifnull(l_salary_income_tax_paid, 0) +
				ifnull(l_capital_gains_tax_paid, 0) +
				ifnull(l_self_assessment_tax_paid, 0) +
				ifnull(l_inheritance_tax_paid, 0) +
				ifnull(l_tax_rebates, 0);

	-- calculate tax to be paid
	-- very much a WIP as UK tax rules are as mad as a honeynut loop and constantly changing
	-- until such time as Ive worked them out, inputting the above values into the HMRC SA form should do the calc for me
/*
	-- personal allowance (nil tax rate band) reduces by £1 for every £2 income over the personal allowance limit
	if l_gross_income > get_variable( 'Income tax nil rate band income limit' ) then
		set l_personal_allowance = get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y')))
									- (l_gross_income - get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y') ) ) )/2;
	else
		set l_personal_allowance = get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y')));
	end if;
	
	-- calculate national insurance due on salary
	if l_gross_income > get_variable('National insurance nil rate band') * 52 then
		set l_national_insurance_calculated =	
						(
							least( 	l_gross_salary, 
									(get_variable('National insurance nil rate band') + get_variable( 'National insurance lower rate band ')) * 52
							)
							- (get_variable('National insurance nil rate band') * 52)
						)
						* get_variable('National insurance lower rate');

	end if;

	if l_gross_income > get_variable('National insurance lower rate band') * 52 then
		set l_national_insurance_calculated = l_national_insurance_calculated +
						(
							l_gross_salary
							- ( get_variable( 'National insurance lower rate band ') * 52 )
						)	
						* get_variable('National insurance higher rate');
	end if;

	-- calculate income tax due on salary
	if l_gross_income > l_personal_allowance then
		set l_income_tax_calculated =	
						(
							least( 	l_gross_salary, 
									l_personal_allowance + get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) 
							)
							- l_personal_allowance
						)
						* get_variable('Income tax lower rate');
	end if;

	if l_gross_income > l_personal_allowance + get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) then
		set l_income_tax_calculated = l_income_tax_calculated +
						(
							least( 	l_gross_salary, 
									l_personal_allowance + get_variable( concat( 'Income tax higher rate band ', date_format(l_tax_year_end, '%Y') ) ) 
							)
							- ( l_personal_allowance 
								+ get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) )
						)	
						* get_variable('Income tax higher rate');
	end if;

	if l_gross_income > l_personal_allowance + get_variable( concat( 'Income tax higher rate band ', date_format(l_tax_year_end, '%Y'))) then
		set l_income_tax_calculated = l_income_tax_calculated +
						(
							l_gross_salary
							- ( l_personal_allowance 
								+ get_variable( concat( 'Income tax higher rate band ', date_format(l_tax_year_end, '%Y'))) )
						)	
						* get_variable( concat('Income tax additional rate ', date_format(l_tax_year_end, '%Y')));
	end if;

	-- calculate income tax due on savings *this is an incorrect calculation*
	if 	l_gross_income > l_personal_allowance 
	then

		if l_gross_income < l_personal_allowance + get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) 
		then
			set l_income_tax_calculated = 	l_income_tax_calculated +
											(l_gross_savings * get_variable('Income tax starter rate'));
		else
			set l_income_tax_calculated = 	l_income_tax_calculated +
											(l_gross_savings * get_variable('Income tax lower rate'));
		end if;

	end if;

	if 	l_gross_income > l_personal_allowance + get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) 
	then
		set l_income_tax_calculated = 	l_income_tax_calculated +
										(l_gross_savings * get_variable('Income tax higher rate'));
	end if;

	if 	l_gross_income > l_personal_allowance + get_variable( concat( 'Income tax higher rate band ', date_format(l_tax_year_end, '%Y'))) 
	then
		set l_income_tax_calculated = 	l_income_tax_calculated +
										(l_gross_savings * get_variable( concat('Income tax additional rate ', date_format(l_tax_year_end, '%Y'))) );
	end if;

	-- calculate income tax due on dividends

	-- calculate capital gains tax due

	*/

/*
	-- tax to pay report 
	call write_report(l_report, null);
	call write_report(l_report, 'Tax report');
	call write_report(l_report, repeat('-', length(l_report_name)) );

	call write_report(l_report, concat(	'Income tax to pay :\t\t\t\t', 
											get_variable('Default currency'), 
											' ',
											ifnull(l_income_tax_calculated, 'ERROR')
									)
						);
	call write_report(l_report, concat(	'National insurance to pay :\t\t\t', 
											get_variable('Default currency'), 
											' ',
											ifnull(l_national_insurance_calculated, 'ERROR')
									)
						);
*/


	-- compile SA report
	call write_report(	l_report, 'Category|Gross of tax|Net of tax|Tax paid', 'table-start');

	if ifnull(l_taxable_taxed_salary,0) != 0 then
		call write_report(	l_report,
					concat(
						'Salary taxed at source|',
						prettify(l_taxable_taxed_salary),
						'|',
						prettify(l_taxable_taxed_salary - l_salary_income_tax_paid),
						'|',
						prettify(l_salary_income_tax_paid)
					),
					'table-middle');
	end if;

	if ifnull(l_taxable_untaxed_salary,0) != 0 then
		call write_report(	l_report,
					concat(
						'Salary untaxed at source|',
						prettify(l_taxable_untaxed_salary),
						'|',
						prettify(null),
						'|',
						prettify(null)
					),
					'table-middle');
	end if;

	if ifnull(l_gross_salary,0) != 0 then
		call write_report(	l_report,
					concat(
						'<b>Total salary</b>|<b>',
						prettify(l_gross_salary),
						'</b>|<b>',
						prettify(null),
						'</b>|<b>',
						prettify(l_salary_income_tax_paid),
						'</b>'
					),
					'table-middle');
	end if;

	if ifnull(l_taxable_taxed_interest,0) != 0 then
		call write_report(	l_report,
					concat(
						'Interest taxed at source|',
						prettify(l_taxable_taxed_interest),
						'|',
						prettify(l_taxable_taxed_interest - l_interest_income_tax_paid),
						'|',
						prettify(l_interest_income_tax_paid)
					),
					'table-middle');
	end if;

	if ifnull(l_taxable_untaxed_interest,0) != 0 then
		call write_report(	l_report,
					concat(
						'Interest untaxed at source|',
						prettify(l_taxable_untaxed_interest),
						'|',
						prettify(null),
						'|',
						prettify(null)
					),
					'table-middle');
	end if;

	if ifnull(l_gross_savings,0) != 0 then
		call write_report(	l_report,
					concat(
						'<b>Total interest</b>|<b>',
						prettify(l_gross_savings),
						'</b>|<b>',
						prettify(null),
						'</b>|<b>',
						prettify(l_interest_income_tax_paid),
						'</b>'
					),
					'table-middle');
	end if;

	if ifnull(l_taxable_dividends,0) != 0 then
		call write_report(	l_report,
					concat(
						'Taxable dividends (already taxed 10% at source)|',
						prettify(l_taxable_dividends + l_dividends_income_tax_paid),
						'|',
						prettify(l_taxable_dividends),
						'|',
						prettify(l_dividends_income_tax_paid)
					),
					'table-middle');
	end if;

	if ifnull(l_taxable_capital_gains,0) != 0 then
		call write_report(	l_report,
					concat(
						'Capital gains (or losses)|',
						prettify(l_taxable_capital_gains),
						'|',
						prettify(null),
						'|',
						prettify(l_capital_gains_tax_paid)
					),
					'table-middle');
	end if;

	if ifnull(l_inheritance,0) != 0 then
		call write_report(	l_report,
					concat(
						'Inheritance|',
						prettify(l_inheritance),
						'|',
						prettify(null),
						'|',
						prettify(l_inheritance_tax_paid)
					),
					'table-middle');
	end if;

	if ifnull(l_self_assessment_tax_paid,0) != 0 then
		call write_report(	l_report,
					concat(
						'Self-assessment (paid this year for previous year)|',
						prettify(null),
						'|',
						prettify(null),
						'|',
						prettify(l_self_assessment_tax_paid)
					),
				'table-middle');
	end if;

	if ifnull(l_tax_rebates,0) != 0 then
		call write_report(	l_report,
					concat(
						'Tax rebates|',
						prettify(null),
						'|',
						prettify(null),
						'|',
						prettify(l_tax_rebates)
					),
					'table-middle');
	end if;

	call write_report(	l_report,
				concat(
					'<b>Total</b>|<b>',
					prettify(l_gross_income),
					'</b>|<b>',
					prettify(null),
					'</b>|<b>',
					prettify(l_total_tax_paid),
					'</b>'
				),
				'table-middle');


	-- complete report
	call write_report(	l_report,
				null,
				'table-end');

	-- stick on subject line
	call write_report(	l_report,
				concat(	'UK self assessment tax report  ',
					date_format(l_tax_year_start, '%Y'), 
					'/', 
					date_format(l_tax_year_end, '%Y')
					), 
				'title');

	-- delete previous iterations of report (only the latest is relevant)
	call delete_series('report_uk_tax', concat('1=', l_tax_year_end));

	-- write completed report to variables table
	call post_variable( concat('report_uk_tax(' , l_tax_year_end, ')') , l_report);

	-- call log('DEBUG : END report_uk_tax');

end; -- report_uk_tax
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [R] determines actions and recommendations to maintain target allocations
-- uses the [target=X] attribute in the account comment field (accessed via the GnuCash GUI
-- p_mode=alert : only output where action is required (ie silent on no action; only alert when stuff needs doing)
-- p_mode=report : always provide full listing of target allocations (verbose, for monthly report)
drop procedure if exists report_target_allocations;
//
create procedure report_target_allocations 
	(
		in	p_guid				varchar(32),
		in 	p_mode				varchar(32)
	)
procedure_block : begin
	
	declare l_performance_sensitivity		int default 0; 

	declare	l_account_guid				varchar(32);
	declare	l_commodity_guid			varchar(32);
	declare l_target				decimal(20,6);
	declare l_account_total				decimal(20,6) default 0;
	declare l_target_total				decimal(20,6) default 0;
	declare l_report				text;
	-- declare l_report_header				varchar(500);
	declare l_report_recommendation			varchar(1000);
	declare l_alert_recommendation			text;

	declare l_current_total_value			decimal(20,6) default 0;
	declare l_current_unit_value_native_currency	decimal(20,6) default 0;
	declare l_current_unit_value_default_currency	decimal(20,6) default 0;
	declare l_original_unit_value_default_currency	decimal(20,6) default 0;
	declare l_current_allocation			decimal(20,6) default 0;
	declare l_target_allocation			decimal(20,6) default 0;
	declare l_target_total_value			decimal(20,6) default 0;
	declare l_target_unit_change			decimal(20,6) default 0;
	declare l_predicted_gain			decimal(20,6) default 0;

	declare	l_remainder_cost			decimal(20,6);
	declare	l_sold_cost				decimal(20,6);
	declare	l_average_cost				decimal(20,6);

	-- declare l_performance_signal			int;
	-- declare l_ppo_signal				text;
	-- declare l_so_signal				text;

	declare l_account_list_done 			boolean default false;
	declare l_account_list_done_temp 		boolean default false;

	declare lc_account_list cursor for
		select distinct 
			guid,
			get_account_commodity(guid),
			cast(get_account_attribute(guid,'target') as decimal(20,6))
		from
			account_map
		where
			get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
			and not is_hidden(guid)
			and not is_parent(guid)
			and is_child(guid)
			and get_account_attribute(guid,'target') is not null;

	declare continue handler for not found set l_account_list_done =  true;

	-- call log( concat('DEBUG : START report_target_allocations(', ifnull(p_guid, 'null'), ',', ifnull(p_mode, 'null'), ')' ));

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  	get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
		or get_variable('Customgnucash status') != 'OK'
	then
		call log(concat('WARNING : Report declined to start' ));
		leave procedure_block;
	end if;

	-- call log('DEBUG : report_target_allocations A');

	-- try to play nicely with other procedures
	do is_locked('accounts', 'WAIT');

	set p_mode = ifnull(p_mode,'report');
	set p_guid = ifnull(p_guid, get_account_guid('Assets'));

	-- call log( concat('DEBUG : p_guid=', p_guid));

	-- get current total value for parent account
	-- get sum of targets for parent account (which cant be assumed to be 100)
	select 	sum( get_account_value(guid, get_default_currency_guid(), null, null, false) ),
		sum( cast(get_account_attribute(guid,'target') as decimal(20,6)) )	
	into 	l_account_total,
		l_target_total
	from
		account_map
	where
		get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
		and not is_hidden(guid)
		and not is_parent(guid)
		and is_child(guid)
		and get_account_attribute(guid,'target') is not null;

	-- call log( concat('DEBUG : l_account_total=', ifnull(l_account_total, 'null')));
	-- call log( concat('DEBUG : l_target_total=', ifnull(l_target_total, 'null')));

	-- get sum of targets for parent account (which cant be assumed to be 100)
/*	select 	sum( cast(get_account_attribute(guid,'target') as decimal(20,6)) )
	into 	l_target_total
	from
		account_map
	where
		get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
		and not is_hidden(guid)
		and not is_parent(guid)
		and is_child(guid)
		and get_account_attribute(guid,'target') is not null;
*/
	-- loop through each account to be assessed
	open lc_account_list;	
	set l_account_list_done = false;

	account_list_loop : loop

		-- call log( concat('DEBUG : NEW LOOP account_list_loop'));
		
		fetch lc_account_list 
		into l_account_guid, l_commodity_guid, l_target;

		if l_account_list_done then 
			leave account_list_loop;
		else
			set l_account_list_done_temp = l_account_list_done;
		end if;

		-- call log( concat('DEBUG : l_account_guid=', ifnull(l_account_guid, 'null')));
		-- call log( concat('DEBUG : get_account_long_name=', get_account_long_name(l_account_guid)));
		-- call log( concat('DEBUG : l_commodity_guid=', ifnull(l_commodity_guid, 'null')));
		-- call log( concat('DEBUG : l_target=', ifnull(l_target, 'null')));

		set l_current_total_value = get_account_value( l_account_guid, get_default_currency_guid(), null, null, false);
		set l_current_unit_value_native_currency = get_commodity_price( l_commodity_guid, null);
		set l_target_allocation = l_target * 100 / l_target_total;

		set l_current_allocation = l_current_total_value * 100 / l_account_total;
		set l_target_total_value = l_target_allocation * l_account_total / 100 ;
		set l_current_unit_value_default_currency = convert_value( 
								l_current_unit_value_native_currency, 
								get_commodity_currency(l_commodity_guid), 
								get_default_currency_guid(), 
								null);

		set l_target_unit_change = (l_target_total_value - l_current_total_value) / l_current_unit_value_default_currency ;

		-- call log( concat('DEBUG : l_current_total_value=', ifnull(l_current_total_value, 'null')));
		-- call log( concat('DEBUG : l_current_unit_value_native_currency=', ifnull(l_current_unit_value_native_currency, 'null')));
		-- call log( concat('DEBUG : l_target_allocation=', ifnull(l_target_allocation, 'null')));
		-- call log( concat('DEBUG : l_current_allocation=', ifnull(l_current_allocation, 'null')));
		-- call log( concat('DEBUG : l_target_total_value=', ifnull(l_target_total_value, 'null')));
		-- call log( concat('DEBUG : l_current_unit_value_default_currency=', ifnull(l_current_unit_value_default_currency, 'null')));
		-- call log( concat('DEBUG : l_target_unit_change=', ifnull(l_target_unit_change, 'null')));

		-- averaged estimate predicted gain or loss on a sale (Asset, Stocks only)
		-- and original unit cost, for comparison with proposed purchases
		if 	get_account_type(l_account_guid) in ('ASSET', 'STOCK') then

			-- only attempt to work out original cost if the holding has ever been purchased
			if is_used(l_account_guid) 
			then

				call get_account_costs(l_account_guid, null, null, l_remainder_cost, l_sold_cost, l_average_cost);	
				set l_original_unit_value_default_currency = l_remainder_cost / get_account_units( l_account_guid, null, null) ;

				-- call log( concat('DEBUG : l_remainder_cost=', ifnull(l_remainder_cost, 'null')));
				-- call log( concat('DEBUG : l_sold_cost=', ifnull(l_sold_cost, 'null')));
				-- call log( concat('DEBUG : l_average_cost=', ifnull(l_average_cost, 'null')));
				-- call log( concat('DEBUG : l_original_unit_value_default_currency=', ifnull(l_original_unit_value_default_currency, 'null')));

				if l_target_unit_change < 0 then
					set l_predicted_gain = 
						( abs(l_target_unit_change) * l_current_unit_value_default_currency ) -- current value of l_target_unit_change units
						-
						( abs(l_target_unit_change) * l_original_unit_value_default_currency ); -- initial (average) cost of l_target_unit_change units
				else
					set l_predicted_gain = 0;
				end if; -- if l_target_unit_change < 0

			end if; -- if is_used(l_account_guid) 

			set l_report_recommendation = null;
			set l_alert_recommendation = null;

			-- compile report
			if abs( l_target_total_value - l_current_total_value) > get_variable('Trivial value') then

				-- call log('DEBUG : report_target_allocations B');
	
				set l_report_recommendation = concat(
								if( l_target_unit_change < 0, 'SELL ', 'BUY '),
								prettify( floor ( abs( l_target_unit_change ))),
								' units at ',
								get_commodity_mnemonic( get_account_currency( l_account_guid ) ) ,
								prettify( round ( l_current_unit_value_default_currency,2)) ,
								' for a total of ',
								get_constant('Default currency') ,
								prettify( floor( abs( l_target_total_value - l_current_total_value)))
							);
				
				if is_used(l_account_guid) then

					-- call log('DEBUG : report_target_allocations C');

					if l_target_unit_change < 0 then

						-- call log('DEBUG : report_target_allocations D');

						if ifnull(l_predicted_gain,0) != 0 then
							set l_report_recommendation = concat(	l_report_recommendation,
												'</br>(Predicted ',
												if(ifnull(l_predicted_gain,0) < 0, 'loss ', 'gain '), 
												get_constant('Default currency'), 
												prettify( floor( abs( ifnull(l_predicted_gain,0)))),
												')'
												);
						end if;
									
					elseif l_target_unit_change > 0 then

						-- call log('DEBUG : report_target_allocations E');

						set l_report_recommendation = concat(	l_report_recommendation,
										'</br>(New unit price is ', 
										prettify( abs( 	l_current_unit_value_default_currency 
												- l_original_unit_value_default_currency) * 100
												/ 
												l_original_unit_value_default_currency
										),
										'% ',
										if(l_current_unit_value_default_currency > l_original_unit_value_default_currency, 
											'higher', 'lower'),
										' than average purchase price)'
									);
					end if; -- if l_target_unit_change < 0

				end if; -- if is_used(l_account_guid) 

				if  p_mode = 'alert' then

					-- call log('DEBUG : report_target_allocations F');
	
					-- call log( concat('DEBUG : get_signal(''', l_commodity_guid, ''',', l_target_unit_change, ',', l_predicted_gain, ', null);' ));
					set l_alert_recommendation = get_signal(l_commodity_guid, l_target_unit_change, l_predicted_gain, null);
					-- call log( concat('DEBUG : l_alert_recommendation=', ifnull(l_alert_recommendation, 'null')));
					
					-- writing report line for 'alert' types
					if l_alert_recommendation is not null then

						-- call log('DEBUG : report_target_allocations G');

						call write_report(	l_report,
									concat(
										get_account_short_name(l_account_guid),
										'|',
										ifnull(l_report_recommendation, '&nbsp;'),
										'|',
										ifnull(l_alert_recommendation, '&nbsp;')
									),
									'table-middle'
								);

					end if; 


				else -- if report is not an alert

					-- call log('DEBUG : report_target_allocations H');

					-- writing report line for 'report' types
					call write_report(	l_report,
								concat(
									get_account_short_name(l_account_guid),
									'|',
									prettify( l_current_total_value ),
									'|',
									prettify( l_current_allocation ),
									'|',
									prettify( l_target_allocation ),
									'|',
									ifnull(l_report_recommendation, '&nbsp;')
								),
								'table-middle'
							);

				end if; -- if p_mode = 'report'

			end if; -- if abs( target_total_value - current_total_value) > get_variable('Trivial value')

		end if; -- if 	get_account_type(l_account_guid) in ('ASSET', 'STOCK')

		set l_account_list_done = l_account_list_done_temp;

	end loop;

	close lc_account_list;	

	if l_report is not null then

		-- call log('DEBUG : report_target_allocations I');

		-- create table header
		if p_mode = 'alert' then

			-- call log('DEBUG : report_target_allocations J');
			call write_report(	l_report,
						'Holding|Recommendation|Alert',
						'table-start');
		else
			-- call log('DEBUG : report_target_allocations K');
			call write_report(	l_report,
						'Holding|Value|Current<br>allocation (%)|Target<br>allocation (%)|Recommendation',
						'table-start');
		end if;

		-- stick header on in correct place
		-- set l_report = concat(l_report_header, l_report);

		-- complete report
		call write_report(	l_report,
					null,
					'table-end');

		-- stick on subject line
		call write_report(	l_report, 
					concat('Target allocation ', p_mode, ' for "', get_account_short_name(p_guid) , '" account.'), 
					'title');

		-- delete previous iterations of report (only the latest is relevant)
		call delete_series('report_target_allocations', concat('1=', p_guid , ',2=', p_mode));

		-- write completed report to variables table
		call post_variable( concat('report_target_allocations(' , p_guid , ',' , p_mode , ')') , l_report);

	end if;

	-- call log('DEBUG : END report_target_allocations');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [H] System status, self-testing and management routines

-- Create views (MySQL has no synonyms) to required GnuCash tables
-- may need to be periodically re-run if underlying Gnucash DB changes DDL (see event monthly_housekeeping)
-- it relies on Gnucash developers having updated table version numbers to indicate a change
drop procedure if exists create_views;
//
create procedure create_views()
procedure_block : begin

	-- set @g_new_gnucash_version	= null; -- I dont really want these to be global, but prepared statements require it
	-- set @g_new_table_version	= null;
	-- set @g_sql			= null;

	declare l_old_gnucash_version	varchar(100);
	declare l_old_table_version	varchar(100);
	declare l_table_name		varchar(64);
	declare l_view_done 		boolean default false;
	declare l_view_done_temp 	boolean default false;
	declare l_views_changed		boolean default false;
	declare l_tables_checked	boolean default false;
	declare l_views_required	int default 0;
	
	declare lc_view cursor for
		select distinct table_name 
		from information_schema.tables 
		where table_schema = get_constant('Gnucash schema'); 
	declare continue handler for not found set l_view_done =  true;

	-- call log('DEBUG : START create_views');

	-- check that expected variables are set
	if 	not exists_variable('Gnucash schema')
		or not exists_variable('Account separator')
	then
		call log('ERROR : Cannot start procedure create_views() as required variables unavailable');
		leave procedure_block;
	end if;

	-- get reported gnucash version
	set l_old_table_version = ifnull(get_variable('Gnucash.version'), 'unknown');
	set @g_sql = concat('select table_version into @g_new_gnucash_version from ', get_constant('Gnucash schema'), '.versions where table_name = ''Gnucash'' ');
	prepare gnucash_version from @g_sql;
	execute gnucash_version;

	-- work through each table
	open lc_view;	
	set l_view_done = false;

	view_loop : loop
		
		fetch lc_view 
		into l_table_name;
	
		if l_view_done then 
			leave view_loop;
		else
			set l_view_done_temp = l_view_done;
		end if;

		-- keep a tally of # views required
		set l_views_required = l_views_required + 1;

		-- check table versions to see if a view needs to be recreated
		set l_old_table_version = get_variable( concat(l_table_name, '.version'));
		set @g_sql = concat('select table_version into @g_new_table_version from ', get_constant('Gnucash schema'), '.versions where table_name = ''', l_table_name, ''' ' );
		prepare table_version from @g_sql;
		execute table_version;
		set l_tables_checked = true;

		-- if table is new to customgnucash, or its version has been changed, then create view	
		if 	l_old_table_version is null 
			or l_old_table_version != @g_new_table_version 
			or l_old_gnucash_version != @g_new_gnucash_version
		then
			-- create view
			set @g_sql = concat('create or replace view ', l_table_name , ' as select * from ' , get_constant('Gnucash schema'), '.' , l_table_name);
			prepare create_view from @g_sql;
			execute create_view;
			set l_views_changed = true;

			-- update local record of GnuCash table versions
			call delete_variable(concat(l_table_name, '.version'));
			call post_variable(concat(l_table_name, '.version'), @g_new_table_version);

			-- log whats been done
			call log( concat('INFORMATION : Created view ', schema(), '.' , l_table_name , ' to table ' , get_constant('Gnucash schema') , '.' , l_table_name));

			-- special case for accounts table	
			-- this view is used instead of any mysql recursive function calls which would make account tree traversal more elegant
			if l_table_name = 'accounts' then

				-- note : mysql view do not support inline variables, so function call get_constant('Account separator') is reqd
				-- note : mysql concat has a hard limit of 1024 characters
				create or replace view account_map as
				    select distinct
					accounts.guid,
					upper(accounts.name) as short_name,
					upper(
						trim(get_constant('Account separator') from 
							replace(
								concat(
									ifnull(p10.name,''),
									get_constant('Account separator'),
									ifnull(p9.name, ''),
									get_constant('Account separator'),
									ifnull(p8.name, ''),
									get_constant('Account separator'),
									ifnull(p7.name, ''),
									get_constant('Account separator'),
									ifnull(p6.name, ''),
									get_constant('Account separator'),
									ifnull(p5.name, ''),
									get_constant('Account separator'),
									ifnull(p4.name, ''),
									get_constant('Account separator'),
									ifnull(p3.name, ''),
									get_constant('Account separator'),
									ifnull(p2.name, ''),
									get_constant('Account separator'),
									ifnull(p1.name, ''),
									get_constant('Account separator'),
									accounts.name),
							'Root Account',	'')
						)
					) as long_name,
					get_element(
						concat(
							ifnull(p10.guid,''),
							get_constant('Account separator'),
							ifnull(p9.guid, ''),
							get_constant('Account separator'),
							ifnull(p8.guid, ''),
							get_constant('Account separator'),
							ifnull(p7.guid, ''),
							get_constant('Account separator'),
							ifnull(p6.guid, ''),
							get_constant('Account separator'),
							ifnull(p5.guid, ''),
							get_constant('Account separator'),
							ifnull(p4.guid, ''),
							get_constant('Account separator'),
							ifnull(p3.guid, ''),
							get_constant('Account separator'),
							ifnull(p2.guid, ''),
							get_constant('Account separator'),
							ifnull(p1.guid, ''),
							get_constant('Account separator'),
							accounts.guid),
					2, get_constant('Account separator') ) as root_guid
				    from
					accounts
					    left outer join
					accounts p1 ON accounts.parent_guid = p1.guid
					    left outer join
					accounts p2 ON p1.parent_guid = p2.guid
					    left outer join
					accounts p3 ON p2.parent_guid = p3.guid
					    left outer join
					accounts p4 ON p3.parent_guid = p4.guid
					    left outer join
					accounts p5 ON p4.parent_guid = p5.guid
					    left outer join
					accounts p6 ON p5.parent_guid = p6.guid
					    left outer join
					accounts p7 ON p6.parent_guid = p7.guid
					    left outer join
					accounts p8 ON p7.parent_guid = p8.guid
					    left outer join
					accounts p9 ON p8.parent_guid = p9.guid
					    left outer join
					accounts p10 ON p9.parent_guid = p10.guid
				    where
					get_commodity_mnemonic(get_account_commodity(accounts.guid)) != 'template';
			end if;

			call log( concat('INFORMATION : Created view ' , schema() , '.account_map to table ' , get_constant('Gnucash schema') , '.' , l_table_name));

		end if;

		set l_view_done = l_view_done_temp;

	end loop;

	close lc_view;

	-- update local record of Gnucash version
	if l_old_gnucash_version != @g_new_gnucash_version then
		call delete_variable('Gnucash.version');
		call post_variable('Gnucash.version', @g_new_gnucash_version);
	end if;

	if ifnull(get_variable('Expected # views'),0) != l_views_required + 1 then
		call delete_variable('Expected # views');
		call post_variable('Expected # views', l_views_required + 1); -- needs to be '+1' to include account_map
	end if;

	-- clean up
	deallocate prepare gnucash_version;
	if l_tables_checked then 
		deallocate prepare table_version; 
	end if;
	if l_views_changed then 
		deallocate prepare create_view; 
	end if;
	set @g_new_gnucash_version = null;
	set @g_new_table_version = null;
	set @g_sql = null;

	-- call log('DEBUG : END create_views');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- rather crude procedure to log skipped events
-- MySQL has no built-in rescheduler, in case an event is skipped (because the computer is powered off at the scheduled time, for example)
-- this procedure needs to be scheduled itself for it to work
-- cant create an event or procedure from within a procedure and begin..end blocks in prepared SQL returns syntax errors
-- this procedure was originally intended to resubmit jobs, but I cant work out how to do it, so it just logs the fact instead
drop procedure if exists reschedule;
//
create procedure reschedule()
procedure_block: begin

	declare l_event_name			varchar(64);
	declare l_event_hour			int;
	declare l_event_last_execution_date	varchar(20);
	declare l_interval_value		varchar(256);
	declare l_interval_field		varchar(18);
	declare l_events_done_temp		boolean default false;
	declare l_events_done			boolean default false;

	declare lc_events cursor for
		select 	events.event_name,
			hour(events.starts),
			date_format(ifnull(events.last_executed, starts),'%Y-%m-%d %H:%i:%S'),
			events.interval_value,
			events.interval_field
		from 	information_schema.events events
		where 	events.event_schema = schema()
		and	events.status = 'ENABLED'
		and	events.event_type = 'RECURRING'
		and	current_timestamp > starts
		and	(current_timestamp < ends or ends is null);
	declare continue handler for not found set l_events_done =  true;

	-- call log('DEBUG : START reschedule');	

	-- work through each event
	open lc_events;	
	set l_events_done = false;
	
	events_loop: loop
		
		fetch 	lc_events 
		into 	l_event_name, 
			l_event_hour,
			l_event_last_execution_date, 
			l_interval_value, 
			l_interval_field;
	
		if l_events_done then 
			leave events_loop;
		else
			set l_events_done_temp = l_events_done;
		end if;

		-- Calculate expected execution date
		-- have to use prepared SQL because l_interval_field could be DAY or MONTH or YEAR etc
		set @g_sql = 	concat(	'select date_format(date_add(''', 
					l_event_last_execution_date, 
					''', interval ', 
					convert(l_interval_value,char), 
					' ', 
					l_interval_field,
					'), ''%Y-%m-%d %H:%i:%S'') into @g_expected_execution_date'
				);
		-- call log( concat('DEBUG: [1] @g_sql="', @g_sql, '"'));
		prepare d_sql from @g_sql;
		execute d_sql;
			
		-- if time has passed the expected execution date, force it to run at the next available time that agrees with the original start hour
		if current_timestamp > str_to_date(@g_expected_execution_date, '%Y-%m-%d %H:%i:%S') then

			-- Mariadb 10.1.30 : #1295 - This command is not supported in the prepared statement protocol yet
			-- bring schedule forward
			-- set @g_sql = concat(
			--		'alter event ', l_event_name,
			--		' on schedule every ', l_interval_value , ' ', l_interval_field,
			--		' starts str_to_date( ''', 
			--			if(	hour(current_timestamp) < l_event_hour,
			--				date_add( from_days(to_days( current_timestamp )), interval l_event_hour hour ),
			--				date_add( from_days(to_days( current_timestamp )), interval (24 + l_event_hour) hour )
			--			),
			--		''', ''%Y-%m-%d %H:%i:%S'')'
			--	);
			-- call log( concat('DEBUG: [2] @g_sql="', @g_sql, '"'));
			-- prepare d_sql from @g_sql;
			-- execute d_sql;

			-- - set @g_sql = trim(regexp_replace(l_event_definition, '(begin|end)\s?(\r|$)', ''));
			-- - call log( concat('DEBUG : ', @g_sql));
			-- - prepare d_sql from @g_sql;
			-- - execute d_sql;	
			-- - call log( concat('INFORMATION : resubmitted event ', l_event_name ));

			call log(  concat('WARNING : event ''', l_event_name, ''' did not run at expected time ''', @g_expected_execution_date, '''.'));
		end if;
	
		set l_events_done = l_events_done_temp;

	end loop;

	close lc_events;

	deallocate prepare d_sql; 
	set @g_sql = null;

	-- call log('DEBUG : END reschedule');	
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- [RW] Runs Gnucash GUI schedule
drop procedure if exists run_schedule;
//
create procedure run_schedule()
procedure_block : begin

	declare l_schedule_guid		varchar(32);
	declare l_split_guid		varchar(32);
	declare l_from_account		varchar(32); 
	declare l_to_account		varchar(32); 
	declare l_amount		decimal(20,6);
	declare l_mult			int(11);
	declare l_period_type		varchar(2048);
	declare l_date			date; 
	declare l_description		varchar(2048);
	declare l_schedule_done_temp	boolean default false;
	declare l_schedule_done		boolean default false;

	declare lc_schedule cursor for
		select distinct
			schedxactions.guid,
			if(length(trim(transactions.description)) != 0, transactions.description, schedxactions.name),
			get_slot( get_slot(splits.guid, 'sched-xaction'), 'sched-xaction/account'),
			to_account.account,
			get_slot( get_slot(splits.guid, 'sched-xaction'), 'sched-xaction/credit-formula'),
			recurrences.recurrence_mult,
			recurrences.recurrence_period_type,
			ifnull( schedxactions.last_occur, recurrences.recurrence_period_start )
			
		from schedxactions 
			join splits 			on schedxactions.template_act_guid = splits.account_guid 
			join transactions		on splits.tx_guid = transactions.guid
			join recurrences 		on schedxactions.guid = recurrences.obj_guid 
			join (
				select distinct
					schedxactions.guid as schedxactions_guid,
					get_slot( get_slot(splits.guid, 'sched-xaction'), 'sched-xaction/account') as account
				from schedxactions 
					join splits on schedxactions.template_act_guid = splits.account_guid 
				where
					ifnull(get_slot( get_slot(splits.guid, 'sched-xaction'), 'sched-xaction/debit-formula'), 0) > 0
				) to_account
					on schedxactions.guid = to_account.schedxactions_guid
		where 	schedxactions.enabled = 1 
			and schedxactions.auto_create = 1 
			and schedxactions.start_date <= now() 
			and (schedxactions.end_date >= now() or schedxactions.end_date is NULL)
            		and ifnull(get_slot( get_slot(splits.guid, 'sched-xaction'), 'sched-xaction/credit-formula'), 0) > 0;

	declare continue handler for not found set l_schedule_done =  true;

	-- call log('DEBUG : START run_schedule');

	open lc_schedule;	
	set l_schedule_done = false;
	
	-- work through each scheduled event
	schedule_loop : loop
		
		fetch 	lc_schedule 
		into 	l_schedule_guid,
			l_description,
			l_from_account, 
			l_to_account, 
			l_amount,
			l_mult,
			l_period_type,
			l_date;
	
		if l_schedule_done then 
			leave schedule_loop;
		else
			set l_schedule_done_temp = l_schedule_done;
		end if;

		repeat

			-- get date of next scheduled transaction
			set l_date =  case l_period_type
						when 'year' 		then 
							date_add( l_date, interval l_mult year )
						when 'month' 		then 
							date_add( l_date, interval l_mult month )
						when 'week' 		then 
							date_add( l_date, interval l_mult week )
						when 'day' 		then 
							date_add( l_date, interval l_mult day )
						when 'end of month'	then 
							last_day( l_date )
					end;

			if l_date <= sysdate() then

				-- call log( concat('DEBUG : Scheduled transaction. From account=',
				--	get_account_long_name(l_from_account), ', To account=',
				--	get_account_long_name(l_to_account), ', Amount=',
				--	convert(l_amount, char), ', Date=',
				--	convert(l_date, char), ', Description=',
				--	l_description
				-- ));

				if 	upper(ifnull(get_variable('Run schedule'), 'FALSE')) = 'TRUE'
					and gnc_lock('schedxactions')
				then

					-- insert transaction
					set l_split_guid = post_split( 
								l_from_account, 
								l_to_account, 
								l_amount, 
								null, 
								l_date, 
								l_description
							);

					-- update schedule table
					if l_split_guid is not null then

						update 	schedxactions
						set	last_occur = l_date,
							instance_count = instance_count + 1
						where	guid = l_schedule_guid;	
		
					end if;

					call gnc_unlock('schedxactions');

				end if;

			end if;

		until l_date > sysdate()
		end repeat;

		set l_schedule_done = l_schedule_done_temp;

	end loop;

	close lc_schedule;

	-- call log('DEBUG : END run_schedule');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//

-- Self-test routine
-- under eternal construction
drop procedure if exists customgnucash_status;
//
create procedure customgnucash_status()
procedure_block : begin

	declare l_report 	text;
	declare l_integer1	int;
	declare l_integer2	int;
	declare l_integer3	int;
	declare l_decimal1	decimal(5,2);
	declare l_date1		timestamp;
	declare l_text1		varchar(500);
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare l_count		int default 0;

	-- dont barf on error for this test procedure; just log what went wrong and continue
	declare continue handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : customgnucash_status : ', l_err_msg ));
	end;

	-- call log('DEBUG : START customgnucash_status');

	-- mark status as undefined
	call delete_variable('CustomGnucash status');

	-- Check version of MySQL / MariaDB is supported
	-- WIP

	-- check that basic variables are set
	if 	not exists_variable('Gnucash schema')
		or not exists_variable('Expected # tables')
		or not exists_variable('Expected # views')
		or not exists_variable('Expected # procedures')
		or not exists_variable('Expected # functions')
		or not exists_variable('Expected # triggers')
		or not exists_variable('Expected # events')
	then
		call post_variable('CustomGnucash status', 'Required variables not set');
		call log('ERROR : Abandoned customgnucash_status because basic variables were not set, which suggests the installation script failed.');
		leave procedure_block;
	end if;

	-- Check expected number of tables
	select 	count( distinct table_name)
	into 	l_integer1
	from 	information_schema.tables
	where 	table_schema = schema()
	and	table_type = 'BASE TABLE';

	if l_integer1 != ifnull(get_variable('Expected # tables'),0) then
		call write_report( concat(l_report, 'Expected ', ifnull(get_variable('Expected # tables'),0), ' tables , found ', l_integer1), 'plain');
	end if;

	-- check expected number of views
	select count( distinct table_name)
	into 	l_integer1
	from 	information_schema.views
	where 	table_schema = schema();

	if l_integer1 != ifnull(get_variable('Expected # views'),0) then
		call write_report( concat(l_report, 'Expected ', ifnull(get_variable('Expected # views'),0), ' views , found ', l_integer1), 'plain');
	end if;

	-- Check expected number of procedures
	select 	count( distinct specific_name)
	into 	l_integer1
	from 	information_schema.routines
	where 	routine_schema = schema()
	and 	routine_type = 'PROCEDURE';

	if l_integer1 != ifnull(get_variable('Expected # procedures'),0) then
		call write_report(l_report, concat('Expected ', ifnull(get_variable('Expected # procedures'),0), ' procedures, found ', l_integer1), 'plain');
	end if;

	-- Check expected number of functions
	select 	count( distinct specific_name)
	into 	l_integer1
	from 	information_schema.routines
	where 	routine_schema = schema()
	and 	routine_type = 'FUNCTION';

	if l_integer1 != ifnull(get_variable('Expected # functions'),0) then
		call write_report(l_report, concat('Expected ', ifnull(get_variable('Expected # functions'),0), ' functions, found ', l_integer1), 'plain');
	end if;

	-- Check expected number of triggers
	select 	count( distinct trigger_name)
	into 	l_integer1
	from 	information_schema.triggers
	where 	trigger_schema = schema();

	if l_integer1 != ifnull(get_variable('Expected # triggers'),0) then
		call write_report(l_report, concat('Expected ', ifnull(get_variable('Expected # triggers'),0), ' triggers, found ', l_integer1), 'plain');
	end if;

	-- Check expected number of events
	select 	count( distinct event_name)
	into 	l_integer1
	from 	information_schema.events
	where 	event_schema = schema();

	if l_integer1 != ifnull(get_variable('Expected # events'),0) then
		call write_report(l_report, concat('Expected ', ifnull(get_variable('Expected # events'),0), ' events, found ', l_integer1), 'plain');
	end if;

	-- Test variable logging routines
	select 	count(*)
	into 	l_integer1
	from 	variable;

	call post_variable('customgnucash_status', 'test');

	select 	count(*)
	into 	l_integer2
	from 	variable;

	if not (exists_variable('customgnucash_status')
		and get_variable('customgnucash_status') = 'test'
		and (l_integer1 + 1) = l_integer2
		)
	then
		call write_report(l_report, 'Failed to write a variable to the customgnucash variables table.', 'plain');
	end if;

	call put_variable('customgnucash_status', 'test1');

	select 	count(*)
	into 	l_integer2
	from 	variable;

	if not (exists_variable('customgnucash_status')
		or get_variable('customgnucash_status') = 'test1'
		or (l_integer1 + 1) = l_integer2
		)
	then
		call write_report(l_report, 'Failed to amend a variable in the customgnucash variables table.', 'plain');
	end if;

	call delete_variable('customgnucash_status');

	select 	count(*)
	into 	l_integer2
	from 	variable;

	if 	exists_variable('customgnucash_status')
		or l_integer1 != l_integer2
	then
		call write_report(l_report, 'Failed to delete a variable from the customgnucash variables table.', 'plain');
	end if;

	-- Test DIY array management routines
	set l_text1 = 'H,Q,Z,P,Z,C';
	call put_element(l_text1, 'A', ',');

	if not	(get_element( sort_array(l_text1, null, null), 1, ',') = 'A'
		and get_element_count( l_text1, ',') = 7
		and get_element_count( sort_array(l_text1, 'u', null), ',') = 6
		)
	then
		call write_report(l_report, 'Array manipluation routines returned unexpected result.', 'plain');
	end if;
	set l_text1 = null;

	-- Test standalone misc routines
	if length(new_guid()) != 32 then
		call write_report(l_report, 'Function new_guid did not return a string of 32 chars', 'plain');
	end if;

	if html_bar(1,null) != '<table class=html_bar bgcolor=black><tr><td>&nbsp;</td></tr></table>' then
		call write_report(l_report, 'Function html_bar did not return the expected string.', 'plain');
	end if;

	-- Test commodity management routines
	if not (exists_commodity(get_variable('Default currency'))
		and is_currency(get_default_currency_guid())
		and get_commodity_price(get_default_currency_guid(),null) = 1
		and get_commodity_mnemonic(get_default_currency_guid()) = get_constant('Default currency')
		)
	then
		call write_report(l_report, 'Commodity manipulation routines returned unexpected result.', 'plain');
	end if;

	-- Test commodity price routines
	

	-- Test account management routines



	-- Mark gnucash db status as undefined
	call delete_variable('Gnucash status');

	-- Check gnucash database can be read from	
	select 	count(*)
	into 	l_integer1
	from 	versions
	where	table_name = 'Gnucash';

	if l_integer1 = 1 then 
		call post_variable('Gnucash status', 'R');
	else
		call write_report(l_report, 'Gnucash database could not be read from.', 'plain');
	end if;

	-- Check gnucash database can be written to (non fatal error; just precludes CustomGnucash RW operations)
	-- attempt a number of times on failure (test occasionally fails spuriously)
	set l_count = 1;
	repeat 
		if 	get_variable('Gnucash status') = 'R'
		then
			begin
				-- MySQL Err 1356, SQLSTATE HY000 occurs when you cant write to the view
				-- declare continue handler for SQLSTATE 'HY000' begin end;
				declare continue handler for 1356 begin end;

				set l_text1 = new_guid();

				insert into versions (table_name, table_version) 
				values 	(l_text1, 1);

				select 	count(*)
				into 	l_integer1
				from 	versions
				where 	table_name = l_text1 and table_version = 1;

				update versions set table_version = 2 where table_name = l_text1;

				select 	count(*)
				into 	l_integer2
				from 	versions
				where 	table_name = l_text1  and table_version = 2;

				delete from versions where table_name = l_text1;

				select 	count(*)
				into 	l_integer3
				from 	versions
				where 	table_version = l_text1;

				-- if the insert, update and delete was successful, and there are no other errors, mark Gnucash DB as read-writable (RW)
				if l_integer1 = 1 and l_integer2 = 1 and l_integer3 = 0 and l_err_code = '00000' 
				then
					call put_variable('Gnucash status', 'RW');
				else
					if l_count >= 5 
					then
						call log( concat('WARNING : [', l_err_code, '] the GnuCash database "', get_constant('Gnucash schema'), '" could not be written to (',l_integer1, ',',l_integer2, ',', l_integer3, ')' ));
					else
						set l_count = l_count + 1;
						do sleep( 1 + (rand() * 4 )); -- wait between 1 and 5 seconds
					end if;
				end if;

				set l_text1 = null;
			end;

		end if;
	until get_variable('Gnucash status') = 'RW' or l_count >= 5
	end repeat;

	-- Test commodity attribute routines (needs access to gnucash db)
	if exists_variable('Gnucash status') then

		select	guid, round_timestamp(current_date), round(rand() * 100, 2)
		into 	l_text1, l_date1, l_decimal1
		from 	commodities
		limit 1;
		
		select 	count(*)
		into 	l_integer1
		from 	commodity_attribute;

		call post_commodity_attribute( trim(l_text1), 'test', l_date1, l_decimal1);

		select 	count(*)
		into 	l_integer2
		from 	commodity_attribute;

		if not (exists_commodity_attribute( trim(l_text1), 'test', l_date1)
			and get_commodity_attribute( trim(l_text1), 'test', l_date1) = l_decimal1
			and (l_integer1 + 1) = l_integer2
			)
		then
			call write_report(l_report, 'Failed to write a variable to the customgnucash commodity_attributes table.', 'plain');
		end if;

		call put_commodity_attribute( trim(l_text1), 'test', l_date1, l_decimal1 + 1);

		select 	count(*)
		into 	l_integer2
		from 	commodity_attribute;

		if not (exists_commodity_attribute( trim(l_text1), 'test', l_date1)
			or get_commodity_attribute( trim(l_text1), 'test', l_date1) = l_decimal1 + 1
			or (l_integer1 + 1) = l_integer2
			)
		then
			call write_report(l_report, 'Failed to amend a variable in the customgnucash commodity_attributes table.', 'plain');
		end if;

		call delete_commodity_attribute( trim(l_text1), 'test', l_date1);

		select 	count(*)
		into 	l_integer2
		from 	commodity_attribute;

		if 	exists_commodity_attribute( trim(l_text1), 'test', l_date1)
			or l_integer1 != l_integer2
		then
			call write_report(l_report, 'Failed to delete a variable from the customgnucash commodity_attributes table.', 'plain');
		end if;

	end if;

	-- log results
	if exists_variable('CustomGnucash status') then
		call put_variable('CustomGnucash status', ifnull(l_report, 'OK'));
	else
		call post_variable('CustomGnucash status', ifnull(l_report, 'OK'));
	end if;

	-- log result
	if get_variable('CustomGnucash status') != 'OK' then
		call log( concat('ERROR : CustomGnucash status is "', get_variable('CustomGnucash status'), '"' ));
	else
		call log( 'INFORMATION : Self test run and passed.');
	end if;

	-- call log('DEBUG : END customgnucash_status');
end;
//
set @procedure_count = ifnull(@procedure_count,0) + 1;
//


-- [I] SCHEDULED EVENTS
-- This is *not* the same thing as the 'scheduled transactions' you can set in the GnuCash GUI; these are internal MySQL scheduled events

-- MySQL users need the EVENT privilege to manage the MySQL event scheduler :
-- For example (as a DBA user) : GRANT EVENT ON customgnucash.* TO customgnucash;

-- MySQL event scheduler needs to be turned on
-- this will turn on the scheduler for *all* your MySQL databases
-- it needs to be performed by a user with SUPER privileges (a DBA user)
-- You may need to set "event-scheduler = ON" in the [mysqld] section of your /etc/my.cnf file to start the scheduler when mysqld starts
-- SET GLOBAL event_scheduler = ON;
-- //

-- All events ar written to honour a lock 'cusomgnucash_event'; this may not actually be necessary, but avoids the risk of overloading the system or 
-- possible data contention issues if events either overrun or are scheduled (by accident or otherwise) to run at the same time. They will wait for 
-- 10 minutes (600 secs) for the lock then fail, so there is a risk that some events may not run at all.

-- [I.1] Housekeeping events

-- Event to keep gnucash prices, dividends and capital gains up to date
drop event if exists daily_housekeeping;
//
create event daily_housekeeping
on schedule 
	every 1 day 
	starts date_add( from_days(to_days( current_timestamp )),  interval (24 + 2) hour )
on completion preserve
comment 'Cleans up prices table and calculates capital gains.'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : daily_housekeeping : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT daily_housekeeping');

	-- check system status
	if 	get_lock('customgnucash_event', 600)
		and get_variable('Customgnucash status') = 'OK'
		and get_variable('Gnucash status') =  'RW'
	then 
		-- check if underlying Gnucash DB has changed and replace stale views if it has (procedure does nothing if nothing required)
		call create_views();
		
		-- clean up prices table (there may be duplicates or missing values)
		call clean_prices(null);

		-- clean up commodities table (there may be commodities that no longer require quoting)
		call clean_commodities();

		-- calculate and post capital gains
		call post_all_gains();

		-- run scheduled transactions (if  get_variable('Run schedule') = 'true'; by default its 'false')
		call run_schedule();

	end if; 

	do release_lock('customgnucash_event');

	-- call log('DEBUG : END EVENT daily_housekeeping');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- ragbag of maintenance functions
drop event if exists weekly_housekeeping;
//
create event weekly_housekeeping
on schedule 
	every 1 week 
	starts date_add( from_days(to_days( current_timestamp )), interval 14 hour ) -- at 14PM
on completion preserve
comment 'Removes obsolete data.'
do
begin	
	declare	l_err_code		char(5) default '00000';
	declare l_err_msg		text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : weekly_housekeeping : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT weekly_housekeeping');

	-- only proceed when lock obtained
	if 	get_lock('customgnucash_event', 600)
		and get_variable('Customgnucash status') = 'OK' 
	then 

		-- clean up customgnucash log table (default : keep last 30 days only)
		if gnc_lock('log') then
			delete from log where datediff(current_timestamp, logdate) > ifnull(get_variable('Keep log'),30);
			delete from log where log like 'DEBUG%' and datediff(current_timestamp, logdate) > 7; -- delete all DEBUG messages more than 7 days old
			call gnc_unlock('log');
		end if;

		-- clean up commodity_attribute table (remove entries without a corresponding commodity in gnucash)
		if gnc_lock('commodity_attribute') then
			delete from commodity_attribute where commodity_guid not in (select guid from commodities);
			call gnc_unlock('commodity_attribute');
		end if;

	end if;

	do release_lock('customgnucash_event');

	-- call log('DEBUG : END EVENT weekly_housekeeping');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- [I.2] Reporting events
-- these are entirely optional and probably need tweaking for personal use
-- the user also needs to regularly schedule : 
-- call get_reports(<n>);
-- to extract <n> created reports to console (where you can email them, or whatever you want to do with them)

-- report anomalies in the system (based on users choice of get_variable('Error level')
drop event if exists report_anomalies;
//
create event report_anomalies
on schedule 
	every 1 day 
	starts date_add( from_days(to_days( current_timestamp )),  interval (24 + 6) hour )
on completion preserve
comment 'Reports anomalies in the system.'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_anomalies : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_anomalies');

	if get_lock('customgnucash_event', 600)
	then

		-- identify missed jobs
		call reschedule();

		-- generate anomaly report
		call report_anomalies();

	end if;

	do release_lock('customgnucash_event');

	-- call log('DEBUG : END EVENT report_anomalies');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report buy/sell signals every day (null report if no signal)
drop event if exists alert_target_allocations;
//
create event alert_target_allocations
on schedule 
	every 1 day 
	starts date_add( from_days(to_days( current_timestamp )),  interval (24 + 3) hour )
on completion preserve
comment 'Reports buy/sell signals on selected stock.'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : alert_target_allocations : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT alert_target_allocations');

	-- give oneself a break over weekends!
	if 	get_lock('customgnucash_event', 600)
		and dayofweek(current_date) not in (1,7) 
	then
		-- call report_target_allocations( get_account_guid('Assets'), 'alert');
		call report_target_allocations( get_account_guid(get_variable('Stocks ISA account'	)), 'alert');
		call report_target_allocations( get_account_guid(get_variable('Pensions account'	)), 'alert');
		call report_target_allocations( get_account_guid(get_variable('Funds and shares account')), 'alert');
	end if;

	do release_lock('customgnucash_event');

	-- call log('DEBUG : END EVENT alert_target_allocations');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report remaining ISA allowance on the first day of each month
-- only useful to UK users
drop event if exists report_remaining_isa_allowance;
//
create event report_remaining_isa_allowance
on schedule 
	every 1 month 
	starts if(	extract(day from current_timestamp) < 1, 
				str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp), 2, '0'), '01'), '%Y%m%d'),
				if(	extract(month from current_timestamp) = 12,
					str_to_date(concat( extract(year from current_timestamp) + 1, '0101'), '%Y%m%d'),
					str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp) + 1, 2, '0'), '01'), '%Y%m%d')
					)
				)
on completion preserve
comment 'Reports how much remains to be used in your UK ISA allowance.'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_remaining_isa_allowance : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_remaining_isa_allowance');
	if get_lock('customgnucash_event', 600)
	then
		call report_remaining_isa_allowance(null);
	end if;

	do release_lock('customgnucash_event');

	-- call log('DEBUG : END EVENT report_remaining_isa_allowance');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report target allocations on the second day of each month
drop event if exists report_target_allocations;
//
create event report_target_allocations
on schedule 
	every 1 month 
	starts if(	extract(day from current_timestamp) < 2, 
				str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp), 2, '0'), '02'), '%Y%m%d'),
				if(	extract(month from current_timestamp) = 12,
					str_to_date(concat( extract(year from current_timestamp) + 1, '0102'), '%Y%m%d'),
					str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp) + 1, 2, '0'), '02'), '%Y%m%d')
					)
				)
on completion preserve
comment 'Reports actual vs target asset allocation.'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_target_allocations : ', l_err_msg ));
	do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_target_allocations');
	if get_lock('customgnucash_event', 600)
	then
		call report_target_allocations( get_account_guid(get_variable('Stocks ISA account'	)), 'report');
		call report_target_allocations( get_account_guid(get_variable('Pensions account'	)), 'report');
		call report_target_allocations( get_account_guid(get_variable('Funds and shares account')), 'report');
	end if;

	do release_lock('customgnucash_event');
	-- call log('DEBUG : END EVENT report_target_allocations');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report asset allocations on the third day of each month
drop event if exists report_asset_allocations;
//
create event report_asset_allocations
on schedule 
	every 1 month 
	starts if(	extract(day from current_timestamp) < 3, 
				str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp), 2, '0'), '03'), '%Y%m%d'),
				if(	extract(month from current_timestamp) = 12,
					str_to_date(concat( extract(year from current_timestamp) + 1, '0103'), '%Y%m%d'),
					str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp) + 1, 2, '0'), '03'), '%Y%m%d')
					)
				)
on completion preserve
comment 'Reports asset allocation by class and location'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_asset_allocations : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_asset_allocations');
	if get_lock('customgnucash_event', 600)
	then
		call report_asset_allocation( get_account_guid('Assets'), 'Location', current_timestamp );
		call report_asset_allocation( get_account_guid('Assets'), 'Asset class', current_timestamp );
		call report_asset_allocation( get_account_guid('Assets'), 'Location:Asset class', current_timestamp );
	end if;

	do release_lock('customgnucash_event');
	-- call log('DEBUG : END EVENT report_asset_allocations');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report gains and losses on the fourth day of each month
drop event if exists report_account_gains;
//
create event report_account_gains
on schedule 
	every 1 month 
	starts if(	extract(day from current_timestamp) < 4, 
				str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp), 2, '0'), '04'), '%Y%m%d'),
				if(	extract(month from current_timestamp) = 12,
					str_to_date(concat( extract(year from current_timestamp) + 1, '0104'), '%Y%m%d'),
					str_to_date(concat( extract(year from current_timestamp), lpad(extract(month from current_timestamp) + 1, 2, '0'), '04'), '%Y%m%d')
					)
				)
on completion preserve
comment 'Reports asset gains'
do
begin	
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_account_gains : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_account_gains');
	if get_lock('customgnucash_event', 600)
	then
		call report_account_gains( get_account_guid('Assets'), null, null );
	end if;

	do release_lock('customgnucash_event');
	-- call log('DEBUG : END EVENT report_account_gains');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- report UK tax every six months (once in June when previous years tax affairs should be settled, and once in December as a reminder for the SA deadline)
-- '-1' means for the last completed tax year
drop event if exists report_uk_tax;
//
create event report_uk_tax
on schedule 
	every 6 month 
	starts if(extract(month from current_timestamp) <= 6, 
				str_to_date(concat( extract(year from current_timestamp), '0630'), '%Y%m%d'),
				str_to_date(concat( extract(year from current_timestamp), '1231'), '%Y%m%d')
			)
on completion preserve
comment 'Reports UK tax details for self-assessment'
do
begin
	declare	l_err_code	char(5) default '00000';
	declare l_err_msg	text;
	declare exit handler for SQLEXCEPTION
	begin
		get diagnostics condition 1
		        l_err_code = RETURNED_SQLSTATE, l_err_msg = MESSAGE_TEXT;
		call log(concat('ERROR : [', l_err_code , '] : report_uk_tax : ', l_err_msg ));
		do release_lock('customgnucash_event');
	end;

	-- call log('DEBUG : START EVENT report_uk_tax');
	if get_lock('customgnucash_event', 600)
	then
		call report_uk_tax( -1 );
	end if;

	do release_lock('customgnucash_event');
	-- call log('DEBUG : END EVENT report_uk_tax');
end;
//
set @event_count = ifnull(@event_count,0) + 1;
//

-- [J] CONFIGURE SYSTEM

-- System control parameters

-- Log DEBUG log messages in log table if Y
call post_variable ('Debug', 'N');
//
-- the name of the schema the GnuCash GUI uses (customgnucash will create synonyms to tables in schema named here)
call post_variable ('Gnucash schema', 'gnucash');
//
-- the default currency used in calculations (value needs to be the default currency set via the Gnucash GUI Edit->Preferences->Accounts)
-- it would be ideal if this was in the GnuCash DB so I wouldnt need to ask, but its in some dodgy text file, so has to be added here again
call post_variable ('Default currency', 'GBP');
//
-- value needs to be that set via Gnucash GUI Edit->Preferences->Accounts 
-- it would be ideal if this was in the GnuCash DB, but its in some dodgy text file, as per default currency
call post_variable ('Account separator', ':');
//
-- some functions store their (expensive) result for later use ('Recalculate' = 'N')
-- if you want them to be recalculated instead (which takes longer), set to 'Y' : SQL> call put_variable('Recalculate', 'Y');
call post_variable ('Recalculate', 'N'); 
//
-- number of days to keep rows in customgnucash.log table (see monthly_housekeeping)
call post_variable ('Keep log', '30'); 
//
-- number of days back to check for missing prices (see clean_prices )
call post_variable ('Price check', '30'); 
//
-- number of months for which no quote was received for a commodity, after which quoting is automatically stopped (see monthly_housekeeping)
call post_variable ('Stop quoting', '6'); 
//
-- number of years back before which incoming quote data is considered too old to bother with (can be increased to load in a heap of old data, for example)
call post_variable ('Maximum quote age', '5'); 
//
-- number of days to calculate EMAs, MACDs or PPOs for at initialisation (the longer the more accurate, given the starting position of an SMA)
call post_variable ('EMA initialisation', '100'); 
//
-- period (in days) over which SO is calculated (see get_commodity_so )
call post_variable('Stochastic oscillator period', '14');
//
-- parameters used in PPO calculations (see get_ppo_signal, get_commodity_ppo)
call post_variable('Short EMA days', '12');
//
call post_variable('Long EMA days', '26');
//
call post_variable('Signal days', '9');
//
-- call post_variable('Sample days', '3');
-- //
call post_variable('Days back', '2');
//
call post_variable('Gradient sensitivity', '0.01');
//
-- percentage difference of a new quote wrt the previous quote above which that new quote will not be loaded (to filter out bad new price data)
call post_variable ('New quote filter', '50'); 
//
-- seconds for which a table lock request will wait before giving up (see gnc_lock )
call post_variable('Lock wait', 60);
//
-- whether to run (or just log) procedure run_schedule that creates GnuCash transactions from the GUI schedule
call post_variable ('Run schedule', 'false');
//

-- Dividends are usually paid 1-4 weeks after the date recorded (in Yahoo Finance historical dividend CSVs, for example). Assumed at 14 days; can be altered as required, but it could be different for each stock, so this value can only ever be an aggregated estimate
call post_variable ('Dividend payment date', 14);
//
-- Sometimes Yahoo Finance quotes values (esp dividends) in a different currency from the share price; override that here 
call post_variable('EMDV.L alternative currency', 'USD');
//
call post_variable('USDV.L alternative currency', 'USD');
//
call post_variable('UDVD.L alternative currency', 'USD');
//
call post_variable('VJPN.L alternative currency', 'USD');
//
call post_variable('VAPX.L alternative currency', 'USD');
//
call post_variable('CRUD.L alternative currency', 'USD');
//

-- Specialised (custom) indices
-- Requires custom routines (probably in OS, not in MySQL) to load in specialised values
call post_variable('Inflation index', 'XXX');
//
call post_variable('House price index', 'XHS');
//

-- Report control parameters
-- Customgnucash reports are stored in a local table and are extracted to console (to email via the OS, or whatever you want to do with them) through the "get_reports" procedure.

-- If 'Error' then report CustomGnucash ERRORs only; if 'Warning' then both WARNINGs and ERRORs, if 'Information', then INFORMATION, WARNING and ERROR reports. 'Off' means no error reporting (report_anomalies) This doesnt affect whether logs are made, just whether they are reported
call post_variable ('Error level', 'Error');
//
-- Dont run CustomGnucash reports if Reports=N
call post_variable ('Report', 'Y');
//
-- CSS style sheet for reports
-- this is prepended to exported (eg emailed) reports to make HTML look pretty
call post_variable ('Report CSS','table.main {border-collapse: collapse;width:100%;} table.main th {font-weight: bold;border: 1px solid black;background:silver} table.main td {border: 1px solid black;} table.html_bar {border-collapse: collapse;border: 0px;} table.html_bar th {border: 0px;} table.html_bar td {border: 0px;} table.null_field {border-collapse: collapse;background:lightgray;width:100%} table.null_field th {border: 0px;} table.null_field td {border: 0px;}');
//
-- the value in "Default Currency" below which reports will not be sent (to filter out piddling changes)
call post_variable ('Trivial value', '1000'); 
//
-- report should explain decision ('Verbose') or just issue the conclusion ('Concise') (mainly for buy/sell decisions) (see function get_signal)
call post_variable ('Explain', 'Verbose'); -- or 'Concise' 
//
-- weightings and caps used by function get_signal
call post_variable('Ignore extremes', 14); -- ignore high/low-since-x-days signals for this may days
//
call post_variable('Vote cap', 5); -- cap buy/sell votes to avoid overwhelming other signals
//
-- call post_variable('Very strong vote', 6); -- votes above which a signal is considered very strong
-- //
-- call post_variable('Strong vote',4); -- botes above which are strong, by implication below which are weak
-- //
call post_variable('Extremes weighting',1); -- weight given to extremes price analysis
//
call post_variable('Short term stochastic oscillator weighting',1);
//
call post_variable('Long term stochastic oscillator weighting',2);
//
call post_variable('Percentage price oscillator weighting',2);
//
call post_variable('Filter weak signals',4); -- votes below which a report will not be sent
//

-- Jurisdiction variables
-- only UK is supported at the moment; other jurisdictions have no code behind them
call post_variable ('Jurisdiction', 'UK');
//
call post_variable ('Default timezone', 'Europe/London');
//
call post_variable ('Tax year end', '6 April');
//

-- Gnucash accounts need to be amended by the user to suit own GnuCash set up
-- to amend post installation, use SQL>put_variable('<variable name>', '<new value>'); 

-- GnuCash accounts used in ISA allowance calculations
-- only applicable in the UK
call post_variable ('Cash ISA account', 'Assets:Cash:Savings accounts:Cash ISA');
//
call post_variable ('Stocks ISA account','Assets:Investments:Stocks and Shares ISA');
//
call post_variable ('Cash account','Assets:Cash:Current account'); -- this is assumed to be the source of ISA contributions
//
call post_variable ('ISA allowance 2014','11800'); -- 2013/2014 ISA allowance
//
call post_variable ('ISA allowance 2015','15000'); -- 2014/2015 ISA allowance
//
call post_variable ('ISA allowance 2016','15240'); -- 2015/2016 ISA allowance
//
call post_variable ('ISA allowance 2017','20000'); -- 2016/2017 ISA allowance
//
call post_variable ('ISA allowance 2018','20000'); -- 2016/2017 ISA allowance
//

-- Pension account(s)
call post_variable ('Pensions account','Assets:Investments:Pensions');
//

-- Funds & shares account(s)
call post_variable ('Funds and shares account','Assets:Investments:Funds and shares');
//

-- GnuCash accounts used in gains and income (ie tax) calculations
-- designed for use in the UK; untested in other jurisdictions
call post_variable ('Interest account', 'Income:Interest');
//
call post_variable ('Dividends account', 'Income:Dividends');
//
call post_variable ('Salary account', 'Income:Salary');
//
call post_variable ('Capital gains account', 'Income:Capital gains');
//
call post_variable ('Inheritance account', 'Income:Inheritance');
//

call post_variable ('Income tax (salary) paid account', 'Expenses:Taxes:Income tax:Salary');
//
call post_variable ('National insurance paid account', 'Expenses:Taxes:National Insurance');
//
call post_variable ('Income tax (interest) paid account', 'Expenses:Taxes:Income tax:Interest');
//
call post_variable ('Income tax rebates account', 'Expenses:Taxes:Income tax:Rebates');
//
call post_variable ('Self assessment tax paid account', 'Expenses:Taxes:Income tax:Self assessment');
//
call post_variable ('Capital gains tax paid account', 'Expenses:Taxes:Capital gains tax');
//
call post_variable ('Inheritance tax paid account', 'Expenses:Taxes:Inheritance tax');
//

-- UK capital gains tax parameters
-- http://www.hmrc.gov.uk/rates/cgt.htm
-- only applicable in the UK
call post_variable ('Capital gains tax lower rate', '0.18');
//
call post_variable ('Capital gains tax higher rate', '0.28'); 
//
call post_variable ('Capital gains tax lower rate band', '32010');
//
call post_variable ('Capital gains tax nil rate band 2013', '10600');
//
call post_variable ('Capital gains tax nil rate band 2014', '10900');
//
call post_variable ('Capital gains tax nil rate band 2015', '11000');
//

-- UK income tax parameters
-- http://www.hmrc.gov.uk/rates/it.htm
-- only applicable in the UK
call post_variable ('Income tax starter rate', '0.1'); 
//
call post_variable ('Income tax lower rate', '0.2'); 
//
call post_variable ('Income tax higher rate', '0.4'); 
//
call post_variable ('Income tax (dividend) lower rate', '0.325'); 
//
call post_variable ('Income tax (dividend) higher rate', '0.375'); 
//
call post_variable ('Income tax nil rate band income limit', '100000');
// 

call post_variable ('Income tax additonal rate 2012', '0.5');
// 
call post_variable ('Income tax nil rate band 2012', '7475');
//
call post_variable ('Income tax starter rate band 2012', '2560');
//
call post_variable ('Income tax lower rate band 2012', '35000');
//
call post_variable ('Income tax higher rate band 2012', '150000');
//

call post_variable ('Income tax additonal rate 2013', '0.5');
//
call post_variable ('Income tax nil rate band 2013', '8105');
//
call post_variable ('Income tax starter rate band 2013', '2710');
//
call post_variable ('Income tax lower rate band 2013', '34370');
//
call post_variable ('Income tax higher rate band 2013', '150000');
//

call post_variable ('Income tax additonal rate 2014', '0.45'); 
//
call post_variable ('Income tax nil rate band 2014', '9440');
//
call post_variable ('Income tax starter rate band 2014', '2790');
//
call post_variable ('Income tax lower rate band 2014', '32010');
//
call post_variable ('Income tax higher rate band 2014', '150000');
//

call post_variable ('Income tax additonal rate 2015', '0.45'); 
//
call post_variable ('Income tax nil rate band 2015', '10000');
//
call post_variable ('Income tax starter rate band 2015', '2880');
//
call post_variable ('Income tax lower rate band 2015', '31865');
//
call post_variable ('Income tax higher rate band 2015', '150000');
//

call post_variable ('Income tax additonal rate 2016', '0.45'); 
//
call post_variable ('Income tax nil rate band 2016', '10000');
//
call post_variable ('Income tax starter rate band 2016', '5000');
//
call post_variable ('Income tax lower rate band 2016', '31765');
//
call post_variable ('Income tax higher rate band 2016', '150000');
//

-- UK national insurance parameters
-- http://www.hmrc.gov.uk/ni/intro/basics.htm#4
-- only applicable in the UK
call post_variable ('National insurance nil rate band', '153'); -- per week, not pa
//
call post_variable ('National insurance lower rate band', '805'); -- per week, not pa
//
call post_variable ('National insurance lower rate', '0.12'); 
//
call post_variable ('National insurance lower rate', '0.02'); 
//

-- UK inheritance tax parameters
-- http://www.hmrc.gov.uk/rates/iht-thresholds.htm
-- only applicable in the UK
call post_variable ('Inheritance tax nil rate band 2014', '325000'); 
//
call post_variable ('Inheritance tax rate 2014', '0.4'); 
//
call post_variable ('Inheritance tax nil rate band 2015', '325000'); 
//
call post_variable ('Inheritance tax rate 2015', '0.4'); 
//

-- Mark system status as undefined
call delete_variable('CustomGnucash status');
//
call delete_variable('Gnucash status');
//
call delete_variable('Expected # tables');
//
call delete_variable('Expected # triggers');
//
call delete_variable('Expected # functions');
//
call delete_variable('Expected # procedures');
//
call delete_variable('Expected # events');
//

-- system self-checking parameters
call post_variable('Expected # tables', @table_count);
//
call post_variable('Expected # triggers', @trigger_count);
//
call post_variable('Expected # functions', @function_count);
//
call post_variable('Expected # procedures', @procedure_count);
//
call post_variable('Expected # events', @event_count);
//

-- [K] CREATE VIEWS

call create_views();
//

-- [L] TEST SYSTEM

-- Run self-check tests
call customgnucash_status();
//

call log( concat ('INFORMATION : CustomGnucash compiled at ', current_timestamp));
//
