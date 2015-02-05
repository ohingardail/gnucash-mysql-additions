/*
GnuCash MySql routines
Author : Adam Harrington
Date : 25 February 2015
*/

-- Prequisites
-- The customgnucash database needs read access to these tables in the gnucash database:
--  accounts, commodities, prices, slots, splits, transactions
-- and write access to these :
--  prices, splits, transactions

-- Customgnucash actions below are marked [R] if they require Readonly access to the gnucash database, [W] Writeonly and [RW] for both.
-- If you have no intention of using [W] procedures, then customgnucash only requires read access to the gnucash database.
-- Adding or changing data in the gnucash database outside the GnuCash application is not supported; be aware of the risk!
-- Specifically, the GnuCash client won't be aware of changes made this way until it is restarted.

-- Limitations
-- This set of routines was intended as a 'toolbox' of useful functions; consequently it sacrifices efficiency for clarity

-- A non-GnuCash database should be used 
-- we want to minimise interference with default GnuCash behaviour or upgrade paths
create schema if not exists customgnucash;
use customgnucash;

-- database flags
-- set sql_mode=ansi;
-- PIPES_AS_CONCAT ('something' || 'something else') it only used when create log messages; concat('something','something else') is more standard
set sql_mode=PIPES_AS_CONCAT;

delimiter //




-- [A.1] Logging table
-- useful (but not critical) to keep, so leave the following drop line commented out if you can
-- xdrop table if exists log;
-- //
create table if not exists log (
	id 		int 		not null auto_increment,
	logdate 	timestamp 	default current_timestamp,
	log 		text		character set utf8,
	primary key (id)
)
//

-- [A.2] User-defined global variables
-- useful (but not critical) to keep, so leave the following drop line commented out if you can
-- xdrop table if exists variable;
-- //
create table if not exists variable (
	variable 	varchar(700) 	not null,
	value 		text		character set utf8,
	logdate 	timestamp 	default current_timestamp on update current_timestamp,
	primary key (variable)
)
//

-- returns true if requested variable exists in customgnucash.variables
drop function if exists variable_exists;
//
create function variable_exists
	(
		p_variable 	varchar(700)
	)
	returns boolean
	deterministic
begin
	declare l_count tinyint;

	select 	count(variable)
	into 	l_count
	from 	variable
	where 	variable = p_variable;

	if l_count = 0 then	return false;
	else return true;
	end if;
end;
//

-- returns value associated with variable in customgnucash.variables
drop function if exists get_variable;
//
create function get_variable
	(
		p_variable 	varchar(700)
	)
	returns text
begin
	declare l_value text default null;
	
	if variable_exists(p_variable) then

		select distinct value
		into 	l_value
		from 	variable
		where 	variable = p_variable;

	end if;

	return l_value;
end;
//

-- adds a new variable/value pair to customgnucash.variables (does nothing if variable already there)
drop procedure if exists post_variable;
//
create procedure post_variable
	(
		p_variable 	varchar(700),
		p_value		text
	)
begin
	if not variable_exists(p_variable) then
		insert into 	variable (variable, value)
		values 		(p_variable, p_value);
	end if;
end;
//

-- updates a variable/value pair to customgnucash.variables (does nothing if variable not already there)
drop procedure if exists put_variable;
//
create procedure put_variable
	(
		p_variable 	varchar(700),
		p_value		text
	)
begin
	if variable_exists(p_variable) then
		update 	variable
		set 	value = p_value	
		where 	variable = p_variable;
	end if;
end;
//

-- deletes a variable/value pair from customgnucash.variables (does nothing if variable not there)
drop procedure if exists delete_variable;
//
create procedure delete_variable
	(
		p_variable 	varchar(700)
	)
begin
	if variable_exists(p_variable) then
		delete from 	variable
		where 		variable = p_variable;
	end if;
end;
//

-- System control parameters
-- the name of the schema the GnuCash GUI uses (customgnucash will create synonyms to tables in schema named here)
call post_variable ('Gnucash schema', 'gnucash');
//
-- the default currency used in calculations (value needs to be the default currency set via the Gnucash GUI Edit->Preferences->Accounts 
call post_variable ('Default currency', 'GBP');
//
-- value needs to be that set via Gnucash GUI Edit->Preferences->Accounts 
call post_variable ('Account separator', ':');
//
-- some functions store their (expensive) result for later use ('Recalculate' = 'N')
-- if you want them to be recalculated instead (which takes longer), set to 'Y' : SQL> call put_variable('Recalculate', 'Y');
call post_variable ('Recalculate', 'N'); 
//
-- number of days to keep rows in customgnucash.log table
call post_variable ('Keep log', '30'); 
//
-- number of days to calculate EMAs or MACDs for at initialisation (the longer the more accurate, given the starting position of an SMA)
call post_variable ('EMA initialisation', '100'); 
//
-- Dump "call log()" errors to console instead of log table if Debug=Y
call post_variable ('Debug', 'N');
//

-- Report control parameters
-- Dont run CustomGnucash reports if Reports=N
call post_variable ('Report', 'Y');
//
-- CSS style sheet for reports
-- this is prepended to reports to make HTML look pretty
call post_variable ('Report CSS','table.main {border-collapse: collapse;width:100%;} table.main th {font-weight: bold;border: 1px solid black;background:silver} table.main td {border: 1px solid black;} table.html_bar {border-collapse: collapse;border: 0px;} table.html_bar th {border: 0px;} table.html_bar td {border: 0px;}');
//
-- function get_performance_signal returns a value -100 to +100 which is a (v crude) aggregate of performance over several periods
-- procedure get_target_allocations can send alerts based on this signal. Increase the value to reduce unwanted alerts; set to 0 to send alerts whenever performance signal deviates from 0 (ie very sensitive)
-- if you want to be alerted of only big performance changes, for example SQL> call put_variable('Performance sensitivity', '10'); 
call post_variable ('Performance sensitivity', '3');
//
call post_variable ('Trivial value', '1000'); -- the value in "Default Currency" below which reports will not be sent
//

-- Jurisdiction variables
-- only UK is supported at the moment; other jurisdictions are not set
call post_variable ('Jurisdiction', 'UK');
//
call post_variable ('Default timezone', 'Europe/London');
//
call post_variable ('Tax year end', '6 April');
//

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

-- SIPP
call post_variable ('SIPP','Assets:Investments:Pensions:SIPP - Hargreaves Lansdown');
//

-- GnuCash accounts used in gains calculations
call post_variable ('Interest account', 'Income:Interest');
//
call post_variable ('Dividends account', 'Income:Dividend Income');
//
call post_variable ('Capital gains account', 'Income:Capital gains');
//

-- GnuCash accounts used in tax calculations
-- only applicable in the UK
call post_variable ('Taxable capital gains account', 'Income:Capital gains:Realised capital gains:Taxable capital gains');
//
call post_variable ('Taxable and taxed salary account', 'Income:Salary:Salary taxed at source');
//
call post_variable ('Taxable and untaxed salary account', 'Income:Salary:Salary untaxed at source');
//
call post_variable ('Taxable and taxed interest account', 'Income:Interest:Taxable interest:Interest taxed at source');
//
call post_variable ('Taxable and untaxed interest account', 'Income:Interest:Taxable interest:Interest untaxed at source');
//
call post_variable ('Taxable dividends account', 'Income:Dividend Income:Taxable dividends');
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

-- [A.3] Create views (MySQL has no synonyms) to required GnuCash tables
-- may need to be periodically re-run if underlying Gnucash DB changes DDL
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
	
	declare lc_view cursor for
		select distinct table_name 
		from information_schema.tables 
		where table_schema = get_variable('Gnucash schema'); 
	declare continue handler for not found set l_view_done =  true;

	-- get reported gnucash version
	set l_old_table_version = get_variable( 'Gnucash.version');
	set @g_sql = concat('select table_version into @g_new_gnucash_version from ', get_variable('Gnucash schema'), '.versions where table_name ="Gnucash"');
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

		-- check table versions to see if a view needs to be recreated
		set l_old_table_version = get_variable( concat(l_table_name, '.version'));
		set @g_sql = concat('select table_version into @g_new_table_version from ', get_variable('Gnucash schema'), '.versions where table_name = "', l_table_name, '"' );
		prepare table_version from @g_sql;
		execute table_version;
		set l_tables_checked = true;

		-- if table is new to customgnucash, or its version has been changed, then create view	
		if 	l_old_table_version is null 
			or l_old_table_version != @g_new_table_version 
			or l_old_gnucash_version != @g_new_gnucash_version
		then
			-- create view
			set @g_sql = concat('create view ', l_table_name , ' as select * from ' , get_variable('Gnucash schema'), '.' , l_table_name);
			prepare create_view from @g_sql;
			execute create_view;
			set l_views_changed = true;

			-- update local record of GnuCash table versions
			call delete_variable(concat(l_table_name, '.version'));
			call post_variable(concat(l_table_name, '.version'), @g_new_table_version);

			-- call log('Created view ' || schema() || '.' || l_table_name || ' to table ' || get_variable('Gnucash schema') || '.' || l_table_name);
		end if;

		set l_view_done = l_view_done_temp;

	end loop;

	close lc_view;

	-- update local record of Gnucash version
	if l_old_gnucash_version != @g_new_gnucash_version then
		call delete_variable('Gnucash.version');
		call post_variable('Gnucash.version', @g_new_gnucash_version);
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
end;
//
-- run it once
call create_views();
//


-- [A.4] MySQL (Ver 15.1 Distrib 5.5.39-MariaDB) doesn't support arrays
-- this workaround uses CSV strings instead

-- gets a +ve or -ve numbered element from a CSV list 
-- ie get_element('A,B,C,D', -2, ',') = 'C'
-- standard MySQL function make_set does something similar
drop function if exists get_element;
//
create function get_element
	(
		p_array		varchar(60000),
		p_index		tinyint,
		p_separator	char(1)
	)
	returns varchar(1000)
	no sql
begin
	declare l_len 		tinyint;
	declare l_count 	tinyint;

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

	return substring_index( substring_index(  p_array , p_separator , p_index ), p_separator, l_len);
end;
//

-- returns the number if elements in an array (ie, a CSV string)
drop function if exists get_element_count;
//
create function get_element_count
	(
		p_array		varchar(60000),
		p_separator	char(1)
	)
	returns tinyint
	no sql
begin
	set p_separator = ifnull(p_separator, ',');
	set p_array = trim( p_separator from p_array);

	return length( p_array ) - length( replace( p_array, p_separator, '' )) + 1;
end;
//

-- adds an element to a CSV string
drop procedure if exists put_element;
//
create procedure put_element
	(
		inout	p_array		varchar(60000),
		in	p_element	varchar(1000),
		in	p_separator	char(1)
	)
	no sql
begin
	set p_separator = ifnull(p_separator, ',');
	if p_element is not null then
		set p_array = trim( p_separator from concat( ifnull(p_array, '' ), p_separator, p_element) );
	end if;
end;
//

-- sorts an array (actually a CSV string)
-- could be done algorithmically via quick sort etc, but decided to hope that native MySQL sorting is better optimised
drop function if exists sort_array;
//
create function sort_array
	(
		p_array		varchar(60000),
		p_separator	char(1),
		p_flag		char(1) -- 'u' for unique sort; default null to include all values, dupes and all
	)
	returns varchar(60000)
begin
	declare l_sorted_array 		varchar(60000);
	declare l_count 		tinyint;
	declare l_element 		varchar(1000);
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
									
		-- call log('START : tally_block');
		
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
				-- call log('LEAVE tally_loop');
				leave tally_loop;
			else
				set l_tally_done_temp = l_tally_done;
			end if;
 
			call put_element(l_sorted_array, l_element, p_separator);

		end loop; -- tally_loop

		close lc_tally;

		-- call log('END : tally_block');
		set l_tally_done = l_tally_done_temp;

	end; -- tally block	
	
	return l_sorted_array;
end;
//

-- [A.5] Miscellaneous standalone routines

-- rounds a timestamp to the appropriate day (so '2010-06-15 23:00:00'-> '2010-06-16 00:00:00' & '2010-01-15 00:00:00'-> '2010-06-15 00:00:00')
-- catering for local time and daylight savings (to deal with GnuCash's tendency to truncate dates to midnight, which is 23:00 UTC the previous day in DST)
-- this is a bit iffy; according to the MySQL & MariaDB doc, timestamp fields are automatically converted to local timestamp on retrieval, 
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

-- Adds a line to the log table (used mainly for debugging, but also used to log CustomGnucash updates to the Gnucash database)
drop procedure if exists log;
//
create procedure log
	(
		p_value		text
	)
begin
	
	-- dump to console, if in debug mode
	if get_variable('Debug') = 'Y' then
		select current_timestamp as '', p_value as '';
	else
		-- otherwise, dump to customgnucash.log table
		insert into log (log)
		values (p_value);
	end if;
end;
//

-- [R] returns true if gnucash is locked by anything other than CustomGnucash itself
-- this is to avoid clasing with the GnuCash application
drop function if exists is_locked;
//
create function is_locked()
	returns boolean
begin
	declare l_lock boolean;

	select 	if(count(*)>0, true, false)
	into 	l_lock
	from 	gnclock 
	where 	hostname != session_user();

	return l_lock;
end;
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

-- returns new random guid for use when inserting rows into GnuCash tables
-- I don't know what algorithm GnuCash actually uses to generate these
drop function if exists new_guid;
//
create function new_guid ()
	returns varchar(32)
	no sql
begin
	return md5(rand());
end;
//

-- returns timestamp of tax year
-- p_index=0 this tax year (ie next April), p_index=-1 last tax year, p_index=-2 start of the last completed tax year etc
drop function if exists get_tax_year_end;
//
create function get_tax_year_end
	(
		p_index	tinyint
	)	
	returns timestamp
begin
	if variable_exists('Tax year end') then
		
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

-- writes a new line to a given variable (for creating long text reports)
-- p_style = plain : no formatting; 
-- table-start : top of html table; 
-- table-end : bottom of html table; 
-- table-middle : middle of html table; 
-- jobname : "JOBNAME:" line at top of report ready for emailing
drop procedure if exists write_report;
//
create procedure write_report
	(
		inout	p_report	text, 	-- for convenience, if this is a string of values delimited by '|' (pipe symobol), it is assumed to be a row in a data table
		in	p_line		varchar(2048),
		in 	p_style		varchar(20)		
	)
	no sql
begin

	-- call log('p_line=' || ifnull(p_line, 'NULL'));

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
				set p_report = concat( 	ifnull(p_report, ''),
							'<table class=main style="width:100%"> <tr> <th> ',
							replace(p_line, '|', '</th> <th> '),
							'</th> </tr>'
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
			when 'jobname' then
				
				set p_report = concat(	'\nJOBNAME:',
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

	-- call log('p_report=' || ifnull(p_report, 'NULL'));
end;
//

-- extracts reports from variables table 
-- designed to be called by a linux function 
-- returns text of p_num (usually 1) reports, then deletes said report from variables table so its not extracted again
-- consequently, it needs to be called from the Linux scheduler regularly (at least once an hour) in order to work through any queue
-- if p_num >1 then >1 reports will be emitted in one lump of text
drop procedure if exists get_report;
//
create procedure get_report
	(
		p_num		tinyint
	)
begin
	declare l_variable	varchar(700);
	declare l_value 	text;
	declare l_report	text;
	declare l_count		tinyint;
	declare l_report_count	tinyint;
	declare l_html_header 	varchar(500);
	declare l_html_footer 	varchar(50);

	set l_count = 1;
	set p_num = ifnull(p_num, 1);

	set l_html_header = concat(	'<html><head><style>',
					get_variable('Report CSS'),
					'</style></head><body>'
				);

	set l_html_footer = '</body></html>';

	-- check how many reports there are
	select 	count(*)
	into 	l_report_count
	from	variable
	where	variable.variable like 'report\_%';

	-- extract reports
	while l_count <= least(p_num, l_report_count) do

		select
			variable.variable,
			variable.value
		into
			l_variable,
			l_value
		from
			variable
		where
			variable.variable like 'report\_%'
		order by
			logdate asc
			-- date(replace( substring_index(variable.variable, '(', -1), ')', '')) asc
		limit 1;

		-- delete report from variables table
		delete from variable
		where 	variable.variable = l_variable;
	
		-- add to list of reports if there is anything to add
		if l_value is not null then
			set l_report = concat( 
						ifnull(l_report,''), 
						if(l_report is not null,'</br>', ''), 
						ifnull(l_value,'') 
					);
		end if;

		set l_count = l_count + 1;

	end while;

	-- return report if there is one
	if l_report is not null then
		select concat(l_html_header, l_report, l_html_footer);
	else
		-- needs to return '' not NULL so calling linux script can see there is nothing in the report
		select '';
	end if;

end;
//

-- some functions store useful series of data in the "variable" table; this function helps extract it
-- variable.value is assumed to be the y-axis value
-- example : in table, where variable="get_commodity_ema(abcdef,20,2010-10-01)" then value="2.2" (and you can get others for 2010-10-02, 2010-10-03 etc)
-- so, get_series('get_commodity_ema', '1=abcdef,2=20' ,3) returns a table with row x=2010-10-01 y=2.2 (and you can get rows for other dates etc)
drop procedure if exists get_series;
//
create procedure get_series
	(
		p_series_name			varchar(64), 	-- the name of the series (usually a function name like 'get_commodity_ema')
		p_criteria			varchar(700), 	-- field specification criteria
		p_x_axis			tinyint		-- the number of the field which will act as x-axis (usually the date field)
	)
begin
	declare l_fieldspec			varchar(700);
	declare l_criterion 			varchar(100);
	declare l_criterion_position 		tinyint;
	declare l_criterion_previous_position 	tinyint;
	declare l_criterion_string 		varchar(100);
	declare l_count 			tinyint;
	declare l_separator			char(1);

	set l_count=1;
	set l_criterion_previous_position=0;

	-- put fieldspec into standard order
	set l_fieldspec = concat('^' , p_series_name , '(');
	set p_criteria = sort_array(p_criteria, ',', 'u');

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
					p_series_name || '(',
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

-- deletes series from variables table
-- example : SQL> delete_series('get_account_costs', '1=3836f80609ee4678e1058e33592031d1'); 
-- deletes *all* previously calculated account costs for account 3836f80609ee4678e1058e33592031d1
drop procedure if exists delete_series;
//
create procedure delete_series
	(
		p_series_name			varchar(64), -- the name of the series (usually a function name like 'get_commodity_ema')
		p_criteria			varchar(700) -- field specification criteria
	)
begin
	declare l_fieldspec			varchar(700);
	declare l_criterion 			varchar(100);
	declare l_criterion_position 		tinyint;
	declare l_criterion_previous_position 	tinyint;
	declare l_criterion_string 		varchar(100);
	declare l_count 			tinyint;
	declare l_separator			char(1);

	set l_count=1;
	set l_criterion_previous_position=0;

	-- put fieldspec into standard order
	set l_fieldspec = concat('^' , p_series_name , '(');
	set p_criteria = sort_array(p_criteria, ',', 'u');

	-- loop through each elementy in user defined fieldspec
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

	-- delete specified series
	delete
	from
		variable
	where
		variable.variable regexp (l_fieldspec);

end;
//

-- [B.1] Commodity management

-- [R] returns true if specified mnemonic ('GBP', 'IUKD.L') exists in the gnucash database
drop function if exists commodity_exists;
//
create function commodity_exists
	(
		p_mnemonic varchar(2048)
	)
	returns boolean
	deterministic
begin
	declare l_count 	tinyint;

	select 	count(commodities.guid)
	into 	l_count
	from 	commodities commodities
	where 	upper(commodities.mnemonic) = upper(p_mnemonic);

	if l_count = 0 then	
		return false;
	else 
		return true;
	end if;
end;
//

-- [R] gets namespace ('EUREX', 'CURRENCY') for specified commodity
drop function if exists get_commodity_namespace;
//
create function get_commodity_namespace
	(
		p_guid 		varchar(32)
	)
	returns varchar(2048)
	deterministic
begin
	declare l_namespace 	varchar(2048);

	select distinct	commodities.namespace 
	into 	l_namespace 
	from 	commodities commodities
	where 	commodities.guid = p_guid
	limit 	1;

	return trim(l_namespace);
end;
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
	deterministic
begin
	if upper(get_commodity_namespace(p_guid)) = 'CURRENCY' then return true;
	else return false;
	end if;
end;
//

-- [R] returns guid for given commodity mnemonic
drop function if exists get_commodity_guid;
//
create function get_commodity_guid
	(
		p_mnemonic 	varchar(2048)
	)
	returns varchar(32)
	deterministic
begin
	declare l_guid 		varchar(32);

	select distinct	commodities.guid 
	into 	l_guid 
	from 	commodities commodities
	where 	upper(commodities.mnemonic) = upper(p_mnemonic) 
	limit 	1;

	return trim(l_guid);
end;
//

-- [R] returns guid for default currency (set up by "call post_variable ('Default currency', 'GBP');"
-- just a convenience function; merely calls get_commodity_guid with correct parameters
drop function if exists get_default_currency_guid;
//
create function get_default_currency_guid()
	returns varchar(32)
	deterministic
begin
	return get_commodity_guid( get_variable('Default currency'));
end;
//

-- [R] returns mnemonic ('GBP', 'IUKD.L) for given commodity guid
drop function if exists get_commodity_mnemonic;
//
create function get_commodity_mnemonic
	(
		p_guid 		varchar(32)
	)
	returns varchar(2048)
	deterministic
begin
	declare l_mnemonic 	varchar(2048);

	select distinct	commodities.mnemonic 
	into 	l_mnemonic 
	from 	commodities commodities
	where 	commodities.guid = p_guid
	limit 	1;

	return trim(l_mnemonic);
end;
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

	select distinct	commodities.fullname 
	into 	l_name 
	from 	commodities commodities
	where 	commodities.guid = p_guid
	limit 	1;

	return trim(l_name);
end;
//

-- [R] returns the currency in which a commodity is quoted
drop function if exists get_commodity_currency;
//
create function get_commodity_currency
	(
		p_guid varchar(32)
	)
	returns varchar(32)
	deterministic
begin
	declare l_guid varchar(32);

	-- short circuit if commodity provided is the default currency
	if p_guid = get_default_currency_guid() then
		return p_guid;
	end if;

	select distinct	prices.currency_guid 
	into 	l_guid
	from 	prices prices
	where 	prices.commodity_guid = p_guid
	limit 	1;

	return trim(l_guid);
end;
//

-- [R] returns the price of a commodity (or currency) on the given date ("now" is default)
-- includes quoted prices and prices derived from actual transactions
-- the unit in which the value is returned is the commodity currency (get_commodity_currency(<commodity_guid>) )
drop function if exists get_commodity_value;
//
create function get_commodity_value
	(
		p_guid		varchar(32),
		p_date		timestamp
	)
	returns 		decimal (15,5)
	deterministic
begin
	declare l_value 	decimal (15,5);

	-- short circuit if commodity provided is the default currency
	if p_guid = get_default_currency_guid() then
		return 1;
	end if;

	-- set default date
	set p_date = ifnull(p_date, current_timestamp);

	select	price
	into 	l_value
	from
		(
		select 	distinct round(prices.value_num/prices.value_denom, 5) as price,
				prices.date as date
		from 	prices prices
		where 	prices.commodity_guid = p_guid
			and prices.date <= p_date
		
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
			join accounts accounts on splits.account_guid = accounts.guid
			join transactions transactions on splits.tx_guid = transactions.guid
		where 
			accounts.commodity_guid = p_guid
			and splits.value_num != splits.quantity_num
			and splits.quantity_num != 0
			and transactions.currency_guid = get_commodity_currency(p_guid)
			and	transactions.post_date <= p_date
		) prices

	order by prices.date desc
	limit 	1;

	return l_value;
end;
//

-- [R] returns the latest date a price was added 
-- this function intentionally ignores (transaction) commodity values in the splits table (unlike get_commodity_value)
-- because at the moment it is only used to update price quotes
drop function if exists get_commodity_latest_date;
//
create function get_commodity_latest_date
	(
		p_guid			varchar(32)
	)
	returns 			timestamp
begin
	declare l_date 			timestamp;

	select distinct date
	into 	l_date
	from 	prices prices
	where 	prices.commodity_guid = p_guid
	order by prices.date desc
	limit 	1;

	return l_date;
end;
//

-- [R] returns the earliest date a price was added 
-- this function ignores (transaction) commodity values in the splits table (unlike get_commodity_value)
drop function if exists get_commodity_earliest_date;
//
create function get_commodity_earliest_date
	(
		p_guid			varchar(32)
	)
	returns 			timestamp
begin
	declare l_date 			timestamp;

	select distinct date
	into 	l_date
	from 	prices prices
	where 	prices.commodity_guid = p_guid
	order by prices.date asc
	limit 	1;

	return l_date;
end;
//

-- [R] returns the latest denominator (fractions of a commodity unit) in which a price is quoted
-- this function intentionally ignores commodity values in the splits table (unlike get_commodity_value)
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

	select 	value_denom
	into 	l_denom
	from 	prices prices
	where 	prices.commodity_guid = p_guid
	order by prices.date desc
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

-- [R] returns the guid of the accounts (home) commodity account 
-- this may be a currency, or a stock, for example)
drop function if exists get_account_commodity;
//
create function get_account_commodity
	(
		p_guid varchar(32)
	)
	returns varchar(32)
	-- deterministic
begin
	declare l_guid varchar(32);

	select distinct	accounts.commodity_guid 
	into 	l_guid
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return trim(l_guid);
end;
//

-- [R] the number of days since the commodity value exceeded the current value
-- for use in determining market price drops or gains
-- p_flag = ">" for "days since the price was this high" and "<" for "days since it was this low"
drop function if exists get_commodity_days_exceeded;
//
create function get_commodity_days_exceeded
	(
		p_guid			varchar(32),
		p_flag			char(1) 
	)
	returns bigint(20)
begin
	declare l_date 			timestamp;
	declare l_value 		decimal(15,5);

	set p_flag = ifnull(p_flag, '<');
	set l_value = get_commodity_value(p_guid, null);

	if p_flag = '<' then
		
		select
			prices.date
		into
			l_date
		from 
			prices
		where
			prices.commodity_guid = p_guid
		and prices.value_num/prices.value_denom < l_value
		order by prices.date desc
		limit 1;
			
	elseif p_flag = '>' then

		select
			prices.date
		into
			l_date
		from 
			prices
		where
			prices.commodity_guid = p_guid
			and prices.value_num/prices.value_denom > l_value
		order by prices.date desc
		limit 1;

	end if;
		
	return datediff(current_timestamp, l_date);

	return null;
end;
//

-- [R] the performance (as %) of a commodity over the period (in days) specified
-- for use in determining market price drops or gains
-- you can compare in a given currency, or by default (p_currency=null)just use the native currency of the holding 
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

	-- get values in commodity native currency
	set l_current_value = get_commodity_value(p_guid, null);
	set l_previous_value = get_commodity_value(p_guid, date_add(current_timestamp, interval p_days day));

		-- convert to specified currency
	if 	p_currency is not null 
		and commodity_exists(p_currency)
		and get_commodity_currency(p_guid) != p_currency 
	then
		set l_current_value = convert_value(l_current_value, get_commodity_currency(p_guid), p_currency, null);
		set l_previous_value = convert_value(l_previous_value, get_commodity_currency(p_guid), p_currency, date_add(current_timestamp, interval p_days day));

	end if;

	return ((l_current_value - l_previous_value) * 100) /  l_previous_value;

	return null;
end;
//

-- [R] returns a buy or sell signal based on performance (long term trend) analysis
-- *highly* experimental!!!
-- NOT TO BE USED TO MAKE BUY OR SELL DECISIONS!
-- really crude method of obtaining signal from performance data
-- assumption on long term mean-reversion (ie, less likely to be true for single or small stocks)
drop function if exists get_performance_signal;
//
create function get_performance_signal
	(
		p_guid		varchar(32)
	)
	returns 		tinyint
begin
	declare l_signal	decimal(15,5);
	declare l_years		decimal(4,2);

	set l_signal=0;
	set l_years=5;

	while l_years > 0 do

		-- long term poor performance is assumed to predict long term gain
		-- which is only likely to be true for indices, and then only sometimes
		set l_signal = 	l_signal
					-
					(
						ifnull(get_commodity_performance(p_guid, round(365.25 * l_years), null),0)
						-- *
						-- l_years/100 -- weighting factor
					);
		
		-- monitor 5 yr, 1 yr, 6 mnth, 3 mnth only
		case l_years
			when 5 then set l_years = 1;
			when 1 then set l_years = 0.5;
			when 0.5 then set l_years = 0.25;
			else set l_years = 0;
		end case;

	end while;

	-- artificially bind the signal range
	if l_signal > 100 then
		set l_signal = 100;
	elseif l_signal < -100 then
		set l_signal = 100;
	end if;

	-- signal ranges from c. -500 to +00 (practically c +1000); need to standardise; assume /100 works
	return round(l_signal/10);

end;
//

-- [R] returns the SMA (simple moving average) of a commodity
-- potentially inaccurate where prices are missing for a date in the specified range
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
	declare l_count 		smallint;
	declare l_value 		decimal(15,5);
	declare l_value_count 		smallint;
	declare l_value_sum		decimal(15,5);
	declare l_sma			decimal(15,5);

	-- initialise
	set l_count = 0;
	set l_value_sum = 0;
	set l_value_count = 0;
	set p_date = round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day))) ; -- default to yesterday (prob no closing price for today)
	set p_days = ifnull(p_days, 30); 

	-- use pre-calculated value if available
	if 	get_variable('Recalculate') = 'N'
		and variable_exists('get_commodity_sma(' || p_guid || ',' || p_days || ',' || p_date || ')')
	then

		set l_sma = get_variable('get_commodity_sma(' || p_guid || ',' || p_days || ',' || p_date || ')');

	else

		while l_count < p_days do

			set l_value = get_commodity_value(p_guid, date_add(p_date, interval - l_count day));
			-- call log('get_commodity_value('|| p_guid || ',' || 'date_add(' || p_date || ', interval - ' || l_count || 'day))=' || ifnull(l_value, 'NULL') );
					
			-- only include non-null values in average, and count how many there are
			if l_value is not null then

				set l_value_sum = l_value_sum + l_value;
				set l_value_count = l_value_count + 1;

			end if;

			set l_count = l_count + 1;

		end while;

		set l_sma = l_value_sum / l_value_count;

		if l_sma is not null then
			call post_variable('get_commodity_sma(' || p_guid || ',' || p_days || ',' || p_date || ')' , l_sma);
		end if;

		return l_sma;

	end if;

	return null;
end;
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
	declare l_loop_count		tinyint;

	-- initialise
	set p_days = abs(ifnull(p_days, 30));
	set p_date = round_timestamp(ifnull(p_date, date_add(current_timestamp, interval - 1 day))) ; -- default to yesterday (prob no closing price for today)
	set l_earliest_date = get_commodity_earliest_date(p_guid);
	set l_date = p_date;

	-- 1. Find latest SMA calculated at or before the date specified (there may be none) as a starting point
	while 	l_date >= l_earliest_date 
			and l_ema is null --  ie short circuit when value found
	do

		-- call log('Looking for old EMA at ' || l_date );
		if 	get_variable('Recalculate') = 'N'
			and variable_exists('get_commodity_ema(' || p_guid || ',' || p_days || ',' || l_date || ')') 
		then
			set l_ema = get_variable('get_commodity_ema(' || p_guid || ',' || p_days || ',' || l_date || ')'); -- get pre-calced SMA
			-- call log('Found old EMA ' || l_ema || ' from ' || l_date );
		else
			set l_date = date_add(l_date, interval -1 day); -- go back one day to look again
		end if;

	end while;

	-- 2. if the latest SMA isnt the one we're looking for, we'll need to calculate it ...
	if l_date != p_date then

		-- 3. if l_ema is null, calculate the starting point (which is actually an sma)
		-- for efficiency & convenience, only go back as far as "get_variable('EMA initialisation')" days
		if l_ema is null then

			set l_date = from_days( to_days( date_add( greatest( l_earliest_date, date_add(current_timestamp, interval - get_variable('EMA initialisation') day )), interval p_days day) ));
			set l_ema = get_commodity_sma(p_guid, p_days, l_date);
			-- call log('Set initialising EMA (SMA) ' || l_ema || ' for ' || l_date );

		end if;

		set l_multiplier = 2 / ( p_days + 1 ); -- get appropriate SMA multiplier

		-- 4. Wind forward from l_date to p_date, calculating ema as you go
		set l_loop_count = 0;
		EMA_LOOP: repeat

			set l_loop_count = l_loop_count + 1;
			set l_date = date_add(l_date, interval 1 day);

			-- call log('Calculating new EMA for ' || l_date );

			set l_ema = 	(get_commodity_value(p_guid, l_date) * l_multiplier)
							+
							(l_ema * (1 - l_multiplier));	
		
			-- store calculated EMA in case its needed in future
			if l_ema is not null then
				call post_variable('get_commodity_ema(' || p_guid || ',' || p_days || ',' || l_date || ')' , l_ema);
			end if;

			-- call log('Set new EMA ' || l_ema || ' for ' || l_date );

			-- debugging short circuit (needs to be commented out foir production use)
			-- if l_loop_count >= 5 then
			-- 	leave EMA_LOOP;
			-- end if;

		-- stop calcuating EMAs once specified date is reached
		until l_date = p_date
		end repeat EMA_LOOP;
		
	end if; -- if l_date != p_date

	return l_ema;
end;
//

-- [R] returns the MACD (moving average convergence-divergence) of a commodity
-- ("12-day commodity EMA" - "26-day commodity EMA") - "9-day EMA of the 12-26 EMA line")
-- very labour intensive to calculate the first time, and only useful in a series (which is automatically stored)
-- results are only likely to be accurate if you have a *full* dataset for at least 100 days
drop procedure if exists get_commodity_macd;
//
create procedure get_commodity_macd
	(
		in p_guid			varchar(32),
		in p_date			timestamp,

		out p_macd_line			decimal(6,3),
		out p_signal_line		decimal(6,3),
		out p_macd_signal_line		decimal(6,3)
	)
procedure_block : begin
	declare l_days				tinyint;
	declare l_counter 			tinyint;
	declare l_date				timestamp;
	declare l_multiplier			decimal(15,5);	
	declare l_earliest_date			timestamp;

	-- set defaults
	set l_days = 9; -- need a 9-day ema macd signal line
	set p_date = round_timestamp(ifnull(p_date, date_add(current_timestamp, interval - 1 day))); -- default to yesterday
	set l_date = p_date;
	-- set l_counter = get_variable('EMA initialisation');
	set l_counter = 10; -- debug only
	set l_earliest_date = get_commodity_earliest_date(p_guid);

	-- 1. Find latest MACD calculated at or before the date specified (there may be none) as a starting point
	while 	l_date >= date_add(l_earliest_date, interval 26 day)
			and (
				p_macd_line is null 
				or p_signal_line is null
				or p_macd_signal_line is null
			) --  ie short circuit when all values found
	do

		-- call log('AA:'|| ifnull(l_date, 'NULL') );

		if 	get_variable('Recalculate') = 'N' then
			
			if variable_exists('get_commodity_macd(' || p_guid || ',' || p_date || ').p_macd_line') then	
				set p_macd_line = get_variable('get_commodity_macd(' || p_guid || ',' || p_date || ').p_macd_line');
			end if;

			if variable_exists('get_commodity_macd(' || p_guid || ',' || p_date || ').p_signal_line') then	
				set p_signal_line = get_variable('get_commodity_macd(' || p_guid || ',' || p_date || ').p_signal_line');
			end if;

			if variable_exists('get_commodity_macd(' || p_guid || ',' || p_date || ').p_macd_signal_line') then	
				set p_macd_signal_line = get_variable('get_commodity_macd(' || p_guid || ',' || p_date || ').p_macd_signal_line');
			end if;

		end if;

		-- go back one day to look again if any one value cannot be found
		if 		p_macd_line 		is null 
			or 	p_signal_line 		is null
			or 	p_macd_signal_line 	is null
		then
			set l_date = date_add(l_date, interval -1 day);
		end if;

	end while;

	-- 2. if the latest MACD isnt the one we're looking for, we'll need to calculate it ...
	if l_date != p_date then

		-- call log('A : '|| ifnull(l_date, 'NULL') );

		-- 3. if p_macd_signal_line is null, calculate the starting point (which is actually an sma)
		-- for efficiency & convenience, only go back as far as "get_variable('EMA initialisation')" days
		if 		p_macd_line 		is null 
			or 	p_signal_line 		is null
			or 	p_macd_signal_line 	is null
		then

			set l_date = from_days( to_days( date_add( greatest( l_earliest_date, date_add(current_timestamp, interval - get_variable('EMA initialisation') day )), interval 30 day) ));
			
			-- call log('B : '|| ifnull(l_date, 'NULL') );

			set l_counter = 0;
			while l_counter < l_days
			do

				-- call log('C : '|| ifnull(l_date, 'NULL') );

				-- use pre-calculated p_macd_line if available, otherwise calculate it
				if 	get_variable('Recalculate') = 'N'
					and variable_exists('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line') 
				then
					set p_macd_line = get_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line');

				else

					set p_macd_line = 	get_commodity_ema(	p_guid, 12, l_date) 
										- 
										get_commodity_ema(	p_guid, 26, l_date);

					call post_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line', p_macd_line);
					set p_signal_line = ifnull(p_signal_line,0) + p_macd_line;

				end if;

				set l_date = date_add( l_date, interval 1 day);
				set l_counter = l_counter + 1;

			end while;

			-- finish off signal_line average
			set p_signal_line = p_signal_line / l_counter;
			call post_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_signal_line', p_signal_line);
			-- call log('Initialising SMA p_signal_line=' || p_signal_line);

		end if; -- if p_macd_line is null 

		set l_multiplier = 2 / ( l_days + 1 ); -- get appropriate SMA multiplier
		-- call log('D');

		-- 4. Wind forward from l_date to p_date, calculating macd and signal lines as you go
		while l_date <= p_date
		do
	
			-- call log('E :' || ifnull(l_date, 'NULL') );

			-- use pre-calculated p_macd_line if available, otherwise calculate it
			if 	get_variable('Recalculate') = 'N'
				and variable_exists('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line') 
			then
				set p_macd_line = get_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line');
			else
				set p_macd_line = 	get_commodity_ema(	p_guid, 12, l_date) 
									- 
									get_commodity_ema(	p_guid, 26, l_date);
				call post_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_line', p_macd_line);
			end if;

			-- use pre-calculated p_signal line if available, otherwise calculate it
			if 	get_variable('Recalculate') = 'N'
				and variable_exists('get_commodity_macd(' || p_guid || ',' || l_date || ').p_signal_line') 
			then
				set p_signal_line = get_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_signal_line');
			else
				set p_signal_line = ( p_macd_line 	*  l_multiplier )
									+
									( p_signal_line * (1 - l_multiplier));
				call post_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_signal_line', p_signal_line);
			end if;

			set p_macd_signal_line = p_macd_line - p_signal_line;
			call post_variable('get_commodity_macd(' || p_guid || ',' || l_date || ').p_macd_signal_line', p_macd_signal_line);

			-- call log('p_macd_line[' || ifnull(l_date, 'NULL') || ']='||  ifnull(p_macd_line, 'NULL'));
			-- call log('p_signal_line[' ||  ifnull(l_date, 'NULL') || ']='||  ifnull(p_signal_line, 'NULL'));
			-- call log('p_macd_signal_line[' ||  ifnull(l_date, 'NULL') || ']='||  ifnull(p_macd_signal_line, 'NULL'));
			
			-- get ready for next date
			set l_date = date_add(l_date, interval 1 day);

		end while; -- while l_date <= p_date

	end if; -- if l_date != p_date then

end;
//

-- [R] returns a buy or sell signal based on MACD (short term trend) analysis
-- *highly* experimental!!!
-- NOT TO BE USED TO MAKE BUY OR SELL DECISIONS!
drop function if exists get_macd_signal;
//
create function get_macd_signal
	(
		p_guid			varchar(32),
		p_date			timestamp
	)
	returns 			varchar(50)
begin
	declare l_macd_line 		decimal(6,3);
	declare l_signal_line		decimal(6,3);
	declare l_macd_signal_line	decimal(6,3);
	declare l_count			tinyint;
	declare	l_macd_array		varchar(100);
	declare	l_signal_array		varchar(100);
	declare	l_macd_signal_array	varchar(100);
	declare l_signal		varchar(50) default '';

	set p_date = round_timestamp(ifnull(p_date, date_add(current_timestamp, interval -1 day))); -- default to yesterday
	set l_signal=0;

	-- calculate MACD for the last 5 days 
	set l_count = 0;
	while l_count < 5 do

		call get_commodity_macd(	
					p_guid, 
					date_add(p_date, interval - l_count day), 
					l_macd_line, 
					l_signal_line, 
					l_macd_signal_line
				);

		-- add to DIY arrays (latest first)
		call put_element(l_macd_array, l_macd_line, null);
		call put_element(l_signal_array, l_signal_line, null);
		call put_element(l_macd_signal_array, l_macd_signal_line, null);

		set l_count = l_count + 1;

	end while;

	-- call log('l_macd_array=' || ifnull(l_macd_array, 'NULL'));
	-- call log('l_signal_array=' || ifnull(l_signal_array, 'NULL'));
	-- call log('l_macd_signal_array=' || ifnull(l_macd_signal_array, 'NULL'));

	-- convergence
	-- V EARLY : if l_macd_signal_line has been decreasing for 4 days
	-- and l_macd_line is -ve : BUY
	-- and l_macd_line is +ve : SELL

	if 		abs(get_element(l_macd_signal_array,1,null)) < abs(get_element(l_macd_signal_array,2,null))
		and	abs(get_element(l_macd_signal_array,2,null)) < abs(get_element(l_macd_signal_array,3,null))
		and	abs(get_element(l_macd_signal_array,3,null)) < abs(get_element(l_macd_signal_array,4,null))
	then

		if l_macd_line > 0 then
			set l_signal='V EARLY BUY';
		elseif l_macd_line < 0 then
			set l_signal='V EARLY SELL';
		end if;

	end if;

	-- crossovers
	-- EARLY : if l_signal_line has just crossed l_macd_line
	-- and l_signal_line is lower than l_macd_line : SELL
	-- and l_signal_line is higher than l_macd_Line : BUY

	if 		get_element(l_signal_array,1,null) - get_element(l_macd_array,1,null) > 0 -- signal today is greater than macd today
		and	get_element(l_signal_array,2,null) - get_element(l_macd_array,2,null) <= 0 -- signal yesterday was less than (or same as) macd yesterday
		and	get_element(l_signal_array,3,null) - get_element(l_macd_array,3,null) < 0 -- signal two days ago was less than macd two days ago
	then
		-- signal is higher than macd and has just crossed it
		set l_signal='EARLY BUY';
	elseif 
			get_element(l_signal_array,1,null) - get_element(l_macd_array,1,null) < 0
		and	get_element(l_signal_array,2,null) - get_element(l_macd_array,2,null) >= 0
		and	get_element(l_signal_array,3,null) - get_element(l_macd_array,3,null) > 0
	then
		-- signal is lower than macd and has just crossed it
		set l_signal='EARLY SELL';
	end if;

	-- LATE : if l_macd_line has just crossed 0
	-- and is now -ve : SELL
	-- and is now +ve : BUY

	if 		get_element(l_macd_array,1,null) > 0 -- macd is +ve today
		and	get_element(l_macd_array,2,null) <= 0 -- macd was -ve or 0 yesterday
		and	get_element(l_macd_array,3,null) < 0
	then
		-- macd has just crossed 0 and is rising
		set l_signal='LATE BUY';
	elseif 
			get_element(l_macd_array,1,null) < 0
		and	get_element(l_macd_array,2,null) >= 0
		and	get_element(l_macd_array,3,null) > 0
	then
		-- macd has just crossed 0 and is falling
		set l_signal='LATE SELL';
	end if;

	-- +ve signal = BUY
	return l_signal;

end;
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

	-- assume date is "now" if null
	set p_date = round_timestamp(ifnull(p_date, current_timestamp));

	-- 1. check to see if part of the calculation has been done already
	/*
	if 	get_variable('Recalculate') = 'N' then

		if variable_exists('convert_value(x,' || p_from || ',' || p_to || ',' || p_date || ')' ) 
		then
			set l_conversion_rate = get_variable('convert_value(x,' || p_from || ',' || p_to || ',' || p_date || ')' );
			return round(p_value * l_primary_conversion, 6);
		end if;

		-- check to see if calc has already been done in reverse
		if variable_exists('convert_value(x,' || p_to || ',' || p_from || ',' || p_date || ')' ) 
		then
			set l_conversion_rate = 1 / get_variable('convert_value(x,' || p_to || ',' || p_from || ',' || p_date || ')' ) ;
			return round(p_value / l_primary_conversion, 6);
		end if;
	end if;
	*/

	-- 2. check if p_from is quoted in p_to units (or vice-versa) allowing a direct (or inverse) conversion
	if l_conversion_rate is null then

		if get_commodity_currency(p_from) = p_to then

			set l_conversion_rate = get_commodity_value(p_from, p_date);

		elseif get_commodity_currency(p_to) = p_from then

			set l_conversion_rate = 1 / get_commodity_value(p_to, p_date);

		end if;

	end if;

	-- 3. check if there is a conversion rate from whatever p_from is quoted in to whatever p_to is quoted in
	-- for example, converting a GBP quoted share price in USD
	if l_conversion_rate is null then

		-- 3.1 find out conversion rate from whatever p_from is quoted in to whatever p_to is quoted in 
		-- ie IUKD is quoted in GBP, USD is quoted in GBP and I want IUKD quoted in USD :
		if get_commodity_currency(p_from) = get_commodity_currency(p_to) then

			-- ie (IUKD->GBP rate) / (USD->GBP rate)
			set l_conversion_rate = get_commodity_value(p_from, p_date) / get_commodity_value(p_to, p_date) ;

		-- or vice-versa
		-- ie USDV is quoted in USD, USD is quoted in GBP and I want USDV quoted in GBP :
		elseif get_commodity_currency( get_commodity_currency(p_from) ) = p_to then

			-- ie (USDV->USD rate) * (USD->GBP rate)
			set l_conversion_rate = get_commodity_value(p_from, p_date) * get_commodity_value(get_commodity_currency(p_from), p_date) ;

		end if;

	end if;

	-- 4. do conversion
	if l_conversion_rate is not null then

		-- call post_variable('convert_value(x,' || p_from || ',' || p_to || ',' || p_date || ')', l_conversion_rate );
		return round(p_value * l_conversion_rate, 6);

	end if;

	-- 5. if we've got this far then conversion couldnt be done
	return null;

end;
//

-- [B.2] Transaction and split management

-- [R] returns true if there is already a relationship between two specified accounts in a split
-- this is irrespective of the 'direction' of the transaction
drop function if exists split_exists;
//
create function split_exists
	(
		p_transaction_guid	varchar(32),
		p_account1		varchar(32),
		p_account2		varchar(32)
	)
	returns 			boolean
begin
	declare l_count 		tinyint;
	
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

-- [R] returns true if there is already a relationship between two specified accounts in any transaction
-- this is irrespective of the 'direction' of the transaction
drop function if exists transaction_exists;
//
create function transaction_exists
	(
		p_account1		varchar(32),
		p_account2		varchar(32)
	)
	returns 			boolean
begin
	declare l_count 		tinyint;

	select		count(transactions.guid)
	into		l_count
	from		
				transactions transactions
		join 	splits splits1
			on	transactions.guid = splits1.tx_guid
		join 	splits splits2
			on	transactions.guid = splits2.tx_guid
	where 				
				splits1.value_num + splits2.value_num = 0
		and 	splits1.account_guid = p_account1
		and 	splits2.account_guid = p_account2;

	if l_count = 0 then
		return false;
	else
		return true;
	end if;
end;
//

-- [R] totals up specified transactions between accounts between two dates 
-- and returns value in specified currency
drop function if exists get_transactions_value;
//
create function get_transactions_value
	(
		p_guid1			varchar(32), -- CSV list of account guids
		p_guid2			varchar(60000), -- CSV list of account guids
		p_currency		varchar(32),
		p_date1			timestamp,
		p_date2			timestamp,
		p_recursive		boolean
	)
	returns 			decimal(20,6)
begin
	declare l_date 			timestamp;
	declare l_value 		decimal(20,6) default 0;

	-- short circuit
	-- if not transaction_exists(p_guid1, p_guid2) then
	-- 	return 0;
	-- end if;

	-- set default currency
	set p_currency = ifnull( p_currency, get_default_currency_guid() );

	-- set default date
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions;
	end if;
	set p_date2 = ifnull(p_date2, current_timestamp);

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- get list of p_guid2 subaccounts, if requested
	if ifnull(p_recursive, false) then
		call put_element(p_guid2 , get_account_children( p_guid2, true), ',');
	end if;

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
				p_guid2 regexp concat( '[[:<:]]', splits2.account_guid, '[[:>:]]' )
			and	splits2.tx_guid in
			(
				select		transactions1.guid
				from
							transactions transactions1
					join 	splits splits1
						on	transactions1.guid = splits1.tx_guid	
				where 				
							p_guid1 = splits1.account_guid
					and		transactions1.post_date >= p_date1
					and 	transactions1.post_date <= p_date2
			)
	) transaction_set
	limit 1;
		-- and		splits1.value_num + splits2.value_num = 0;

	return ifnull(round(l_value,6),0);
end;
//

-- [B.3] Account management

-- MySQL 5.5 doesn't support recursive function calls; this would make traversing the GnuCash account tree structure more elegant
-- so, instead, there is a lookup view of the GnuCash accounts to 10 levels. 
-- if a user needs more than 10 levels, the view must be extended
create or replace view account_map as
    select distinct
        accounts.guid,
        upper(accounts.name) as short_name,
        upper(trim(get_variable('Account separator') from replace(concat(ifnull(p10.name, ''),
                                get_variable('Account separator'),
                                ifnull(p9.name, ''),
                                get_variable('Account separator'),
                                ifnull(p8.name, ''),
                                get_variable('Account separator'),
                                ifnull(p7.name, ''),
                                get_variable('Account separator'),
                                ifnull(p6.name, ''),
                                get_variable('Account separator'),
                                ifnull(p5.name, ''),
                                get_variable('Account separator'),
                                ifnull(p4.name, ''),
                                get_variable('Account separator'),
                                ifnull(p3.name, ''),
                                get_variable('Account separator'),
                                ifnull(p2.name, ''),
                                get_variable('Account separator'),
                                ifnull(p1.name, ''),
                                get_variable('Account separator'),
                                accounts.name),
                        'Root Account',
                        ''))) as long_name,
        get_element(concat(ifnull(p10.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p9.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p8.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p7.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p6.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p5.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p4.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p3.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p2.guid, ''),
                        get_variable('Account separator'),
                        ifnull(p1.guid, ''),
                        get_variable('Account separator'),
                        accounts.guid),
                2,
                get_variable('Account separator')) as root_guid
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
        get_commodity_mnemonic(get_account_commodity(accounts.guid)) != 'template'
//

-- [R] returns true if given account name can be found in GnuCash
drop function if exists account_exists;
//
create function account_exists
	(
		p_name 		varchar(2048)
	)
	returns 		boolean
begin
	declare l_count 	tinyint;

	set p_name = upper( trim( get_variable('Account separator') from p_name) );

	if locate(get_variable('Account separator'), p_name) = 0 then

		select 	count(guid)
		into 	l_count
		from 	accounts accounts
		where 	upper( trim( accounts.name)) = p_name;

	else

		select 	count(guid)
		into 	l_count
		from 	account_map
		where 	long_name like concat('%',  p_name);

	end if;

	if l_count = 0 then 
		return false;
	else 
		return true;
	end if;
end;
//

-- [R] returns true if the account identified (by guid) is a placeholder
drop function if exists is_placeholder;
//
create function is_placeholder
	(
		p_guid 	varchar(32)
	)
	returns 	boolean
	deterministic
begin
	declare l_placeholder tinyint;

	select distinct	accounts.placeholder
	into 	l_placeholder 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;
	
	return l_placeholder;
end;
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
	declare l_count tinyint;

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

-- [R] returns true if the account identified (by guid) is hidden
drop function if exists is_hidden;
//
create function is_hidden
	(
		p_guid 	varchar(32)
	)
	returns 	boolean
	deterministic
begin
	declare l_hidden tinyint;

	select distinct	accounts.hidden
	into 	l_hidden 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;
	
	return l_hidden;
end;
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
	declare l_count tinyint;

	select 	count(accounts.guid)
	into 	l_count
	from 	accounts accounts
	where 	accounts.parent_guid = p_guid;

	if l_count = 0 then	
		return false;
	else 
		return true;
	end if;

end;
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

	select 	get_account_type(parent_guid)
	into	l_parent_type
	from	accounts accounts
	where	accounts.guid = p_guid
	limit 1;

	if l_parent_type is null or l_parent_type = 'ROOT' then 
		return false;
	else 
		return true;
	end if;
end;
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

	set p_name = upper( trim( get_variable('Account separator') from p_name));

	if locate(get_variable('Account separator'), p_name) = 0 then

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

	return trim(l_guid);
end;
//

-- returns  guid of root account (ASSETS, INCOME, EQUITY etc)
drop function if exists get_account_root;
//
create function get_account_root
	(
		p_guid varchar(32)
	)
	returns varchar(32)
	deterministic
begin
	declare l_guid	varchar(32);

	select	root_guid
	into l_guid
	from account_map
	where guid = p_guid
	limit 1;

	return l_guid;

end;
//

-- [R] returns the short name of account identified (by guid)
drop function if exists get_account_short_name;
//
create function get_account_short_name
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
	-- deterministic
begin
	declare l_name varchar(2048);

	select distinct	trim( upper( accounts.name ))
	into 	l_name 
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return l_name;
end;
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
	-- deterministic
begin
	declare l_name varchar(2048);

	select distinct	trim( upper( account_map.long_name )) 
	into 	l_name 
	from 	account_map
	where 	account_map.guid = p_guid 
	limit 	1;

	return l_name;
end;
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
	-- deterministic
begin
	return get_commodity_currency( get_account_commodity( p_guid ));
end;
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
	deterministic
begin
	declare l_type varchar(2048);

	select distinct	accounts.account_type 
	into 	l_type
	from 	accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return trim(l_type);
end;
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
	returns varchar(2048)
	-- deterministic
begin
	declare l_guid 			varchar(2048);
	declare l_long_name		varchar(2048);

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

	return trim(l_guid);
end;
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
	-- deterministic
begin
	declare l_all_parents 		varchar(2048);
	declare l_parent 		varchar(32);
	declare l_child			varchar(32);

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
	
	return trim(',' from l_all_parents);
end;
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
	deterministic
begin
	declare l_parent_guid	varchar(32);

	-- do simple check first
	select parent_guid
	into l_parent_guid
	from accounts accounts
	where accounts.guid = p_child_guid;

	if l_parent_guid = p_parent_guid then
		return true;
	else
		-- if simple check returned nothing and a recursive check was requested, look further...
		if  ifnull(p_recursive, false) then

			if locate( get_account_long_name(p_parent_guid), get_account_long_name(p_child_guid) ) > 0 then
				return true;
			end if;

		else
			return false;
		end if;

	end if;
	
	-- if nothing found by this point, return null
	return null;
end;
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
	declare l_counter		tinyint default 1;

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
	declare l_acct_value 		decimal(20,6) default 0;
	declare l_parent_acct 		varchar(2048);
	declare l_date 			timestamp;

	-- call log('START get_account_value');

	-- bail if no account specified
	if p_guid is null then
		return null;
	end if;

	-- set defaults
	set p_children = ifnull(p_children, false);
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions;
	end if;
	set p_date2 = ifnull(p_date2, current_timestamp);

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- if we are adding up children accts also, standardise on default currency
	if p_children = true and p_currency is null then
		set p_currency = get_default_currency_guid();
	else
		-- otherwise just use whatever the account uses (which might be share units) if no currency specified
		set p_currency = ifnull(p_currency, get_account_commodity(p_guid) );
	end if;

	-- if no children account rollup is required (or possible), do a simple sum
	if p_children = false or is_parent(p_guid) is false then

		select		sum(splits.quantity_num/splits.quantity_denom)
		into 		l_acct_value
		from 		splits splits
			join 	transactions transactions 
				on 	splits.tx_guid = transactions.guid
		where 		splits.account_guid = p_guid
			and	transactions.post_date >= p_date1
			and 	transactions.post_date <= p_date2;

		-- convert to specified currency, if any
		if p_currency != get_account_commodity(p_guid) then
			set l_acct_value = convert_value(l_acct_value, get_account_commodity(p_guid), p_currency, p_date2);
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
				and	 	transactions.post_date >= p_date1
				and		transactions.post_date <= p_date2;
		
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
				and	 	transactions.post_date >= p_date1
				and		transactions.post_date <= p_date2;

			end if;
	end if;

	return ifnull(round(l_acct_value,6),0);
end;
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
				null, 
				null, 
				false);
end;
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
			transactions.post_date,
			upper(splits.action),
			case
				when splits.account_guid = p_guid 																			then "3.SELF"
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Dividends account')), true) 		then "2.DIVIDEND"
				-- when is_child_of(splits.account_guid, get_account_guid( get_variable('Capital gains account')), true) 	then "2.CAPITAL GAIN"
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Interest account')), true) 		then "2.INTEREST"
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
			and transactions.post_date <= p_date2
		order by
			transactions.post_date,
			transactions.enter_date,
			class;

	declare continue handler for not found set l_transactions_done =  true;

	-- call log('START get_account_costs');

	-- use earliest and latest transaction dates if none provided
	if p_date2 is null then

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

	-- check if values have already been calculated
	if get_variable('Recalculate') = 'N' then

		if variable_exists('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_remainder_cost' ) 
		then
			set p_remainder_cost = get_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_remainder_cost');
		end if;

		if variable_exists('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_sold_cost' ) 
		then
			set p_sold_cost = get_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_sold_cost');
		end if;

		if variable_exists('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_average_cost' ) 
		then
			set p_average_cost = get_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_average_cost');
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

			-- call log('l_transaction_guid=' || l_transaction_guid);
			-- call log('l_post_date=' || l_post_date);
			-- call log('l_quantity=' || l_quantity);

			-- reset on new transaction
			if l_previous_transaction_guid is null or l_previous_transaction_guid != l_transaction_guid then		
				set l_expense = 0;
			end if;

			if get_account_type(p_guid) in ('STOCK', 'ASSET') then

				-- take a note of expenses for use in later calculation
				if l_class regexp "EXPENSE"	then 
					set l_expense = ifnull(l_expense,0) + l_value;
				end if;

				-- calculate cost of account whenever there is a dividend payment
				if 	l_class regexp "DIVIDEND" 
				and 	l_post_date >= p_date1
				then 
					
					insert into cost_tally
					(	
						select ifnull( sum( (quantity_bought - quantity_sold) * unit_value_bought ), 0)
						from stock_tally
					);

				end if;

				if l_class regexp "SELF" then
								
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
									
									-- call log('l_quantity=' || l_quantity);
									-- call log('END : tally_loop');
																	
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
				if l_class regexp "INTEREST" 
					and l_post_date >= p_date1
					then 

					insert into cost_tally
					values
					( 	get_account_value(p_guid, null, null, l_post_date, false)
						-
						get_transactions_value( p_guid, get_account_guid( get_variable('Interest account')), null, null, l_post_date, true)
						+
						get_transactions_value( p_guid, get_account_guid( get_variable('Income tax (interest) paid account')), null, null, l_post_date, false)
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
			call post_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_remainder_cost' , p_remainder_cost);

			-- calculate original cost of whatever's sold from the account
			select 	ifnull( sum( quantity_sold * unit_value_bought ), 0)
			into 	p_sold_cost
			from 	stock_tally;

			-- store the new result for future use
			call post_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_sold_cost' , p_sold_cost);

		end if;

		-- calculate average cost (at times of dividend or interest payments) over period
		-- this is not likely to be a 100% accurate method of getting % returns on dividends or interest payments
		select 	ifnull(avg(account_cost), 0)
		into 	p_average_cost
		from 	cost_tally
		where 	account_cost > 0;

		-- store the new result for future use
		call post_variable('get_account_costs(' || p_guid || ',' || p_date1 || ',' || p_date2 || ').p_average_cost' , p_average_cost);

	end if; -- if p_remainder_cost is null

	-- debugging only
	-- select * from stock_tally order by id;

	-- call log('END get_account_costs');

end; -- outer block
//

-- [C.1] Reports

-- [R] Returns a table itemising capital gains, dividends and interest returns 
-- in default currency, as absolute %, as % pa
-- may take a v long time if you have many accounts to process
drop procedure if exists report_account_gains;
//
create procedure report_account_gains
	(
		in	p_guid			varchar(32),
		in 	p_date1			timestamp,
		in 	p_date2			timestamp
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
	declare l_report_header			varchar(500);

	-- variables for managing cursors
	declare l_asset_account_done 		boolean default false;
	declare l_asset_account_done_temp 	boolean default false;
	declare lc_asset_account cursor for
		select distinct guid
		from 	account_map
		where
			root_guid = get_account_guid('ASSETS')
			and is_child_of(guid, p_guid, true)
			and not is_placeholder(guid)
			and is_used(guid)
			and  (	( get_account_type(guid) in ('ASSET', 'STOCK')
				  and get_account_commodity(guid) != get_default_currency_guid() )
				  -- ASSET or STOCK types need to have a unit value if unrealised gains are to be calculated
				or
				get_account_type(guid) in ('BANK', 'CASH')
			     )
			-- and get_account_attribute(guid, 'ASSET CLASS') not in ('MUTUAL FUND', 'PROPERTY')
			-- I cant calculate capital gains on mutual funds or property as I dont know their unit value
		order by
			long_name;			
	declare continue handler for not found set l_asset_account_done =  true;
	
	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
	then
		call log('Report report_account_gains declined to start; Gnucash status = ' || get_variable('Gnucash status') || 'Reporting = ' || get_variable ('Report') );
		leave procedure_block;
	end if;

	-- call log('START report_account_gains');

	-- set default dates (strip off timestamps from date)
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	transactions;
	end if;
	set p_date1 = round_timestamp(ifnull(p_date1, current_timestamp));

	if p_date2 is null then
		select 	max(post_date)
		into 	p_date2
		from 	transactions;
	end if;
	set p_date2 = round_timestamp(ifnull(p_date2, current_timestamp));

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- call log('p_date1 = ' 	|| ifnull(p_date1,0));
	-- call log('p_date2 = ' 	|| ifnull(p_date2,0));

	-- set default account ID to work from (the root ASSET account)
	set p_guid = ifnull(p_guid, get_account_guid('ASSETS'));

	-- dont run this report again if the output still exists
	-- ideally, this should check for min date of transactions for account -> max date thereof, but these are only calced later 
	if not variable_exists('report_account_gains(' || p_guid || ',' || p_date1 || ',' || p_date2 || ')')  then

		open lc_asset_account;	
		set l_asset_account_done = false;
	
		-- loop over each account returned by the cursort
		asset_account_loop : loop
		
			fetch lc_asset_account into l_guid;
	
			if l_asset_account_done then 
				-- call log('LEAVE asset_account_loop');
				leave asset_account_loop;
			else
				set l_asset_account_done_temp = l_asset_account_done;
			end if;

			-- call log('Processing account : ' || l_guid );

			-- check p_date2 is not later than latest transaction in account 
			select 	min(dates.date)
			into 	l_latest_transaction_date
			from
			(
				select  max(post_date) as date
				from 	transactions
					join splits
						on transactions.guid = splits.tx_guid
				where	splits.account_guid = l_guid
				and 	post_date <= current_timestamp
				-- having	min(post_date) != max(post_date)
				union
				select 	p_date2
			) dates;

			-- check p_date1 is not earlier than earliest transaction in account 
			select 	max(dates.date)
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

			-- call log('l_latest_transaction_date = ' 	|| ifnull(l_latest_transaction_date,0));
			-- call log('l_earliest_transaction_date = ' 	|| ifnull(l_earliest_transaction_date,0));

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

			-- call log('l_v_latest_transaction_date = ' 	|| ifnull(l_v_latest_transaction_date,0));
			-- call log('l_v_earliest_transaction_date = ' 	|| ifnull(l_v_earliest_transaction_date,0));

			-- clear values from last loop
			set l_capital_gains = null;
			set l_account_value = null;
			set l_unrealised_gains = null;
			set l_dividends = null;
			set l_interest = null;

			-- get account value for current timestamp
			set l_account_value = get_account_value(	l_guid, 
									get_default_currency_guid(),
		 							null, 
									p_date2, -- NOT l_latest_transaction_date, 
									false);
			-- call log('l_account_value = ' 	|| ifnull(l_account_value,0));

			-- get specialised cost values		
			call get_account_costs(	l_guid, 
						l_earliest_transaction_date, 
						l_latest_transaction_date, 
						l_remainder_cost, 
						l_sold_cost, 
						l_average_cost);
			-- call log('l_remainder_cost = ' 	|| ifnull(l_remainder_cost,0));
			-- call log('l_sold_cost = ' 	|| ifnull(l_sold_cost,0));
			-- call log('l_average_cost = ' 	|| ifnull(l_average_cost,0));

			-- set and standardise account name 
			set l_account_name = get_account_long_name(l_guid);
			set l_account_name = replace(replace(l_account_name,  concat( substring_index( l_account_name, ':', 2), ':'), ''), ':', ':<br>');

			-- set and standardise account types (CASH and BANK are treated the same way, etc)
			set l_account_type = get_account_type(l_guid);
			-- call log('l_account_type = ' 	|| ifnull(l_years,0));

			set l_years = timestampdiff(DAY, l_earliest_transaction_date, p_date2) / 365;
			-- call log('l_years = ' 	|| ifnull(l_years,0));

			-- add values to report table
			if l_account_type in ('ASSET', 'STOCK') then

				-- call log('ASSET type identified');

				set l_capital_gains = get_transactions_value(	l_guid, 
										get_account_guid( get_variable('Capital gains account')),	
										null, 
										l_earliest_transaction_date, 
										l_latest_transaction_date, 
										true);
				-- call log('l_capital_gains = ' || ifnull(l_capital_gains,0));

				set l_unrealised_gains = l_account_value - l_remainder_cost;
				-- call log('l_unrealised_gains = ' || ifnull(l_unrealised_gains,0));

				if l_account_type = 'STOCK' then

					set l_dividends = get_transactions_value(	l_guid, 
											get_account_guid( get_variable('Dividends account')), 		
											null, 
											l_earliest_transaction_date, 
											l_latest_transaction_date, 
											true);				
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

					-- call log('Writing report line');
					call write_report(	l_asset_report,
								concat(
									if( ifnull(l_account_value,0) = 0,
										concat('<font size=-1><i>', l_account_name, '</i>'),
										l_account_name
									),
									'|',
									if( ifnull(l_capital_gains,0) = 0, '&nbsp;', round(l_capital_gains,2) ),
									'|',
									if( ifnull( l_capital_gains,0 ) = 0 or ifnull( l_sold_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_capital_gains * 100) / l_sold_cost, 2)
									),
									'|',
									if( ifnull( l_capital_gains,0 ) = 0 or ifnull( l_sold_cost,0) = 0, 
										'&nbsp;', 
										round( (l_capital_gains * 100) / (l_sold_cost * l_years ), 2)
									),
									'|',
									if( ifnull(l_unrealised_gains,0) = 0, '&nbsp;', round(l_unrealised_gains,2) ),
									'|',
									if( ifnull(l_unrealised_gains,0 ) = 0 or ifnull( l_remainder_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_unrealised_gains * 100) / l_remainder_cost, 2)
									) ,
									'|',
									if( ifnull( l_unrealised_gains,0 ) = 0 or ifnull( l_remainder_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_unrealised_gains * 100) / (l_remainder_cost * l_years ), 2)
									) ,
									'|',
									if( ifnull(l_dividends,0) = 0, '&nbsp;', round(l_dividends,2) ),
									'|',
									if( ifnull( l_dividends,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_dividends * 100) / l_average_cost, 2)
									),
									'|',
									if( ifnull( l_dividends,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_dividends * 100) / (l_average_cost * l_years ), 2)
									)							
								),
								'table-middle');

				end if; -- if ifnull(l_capital_gains,0) != 0
		
			elseif l_account_type in ('BANK', 'CASH') then

				-- call log('BANK type identified');

				set l_interest = get_transactions_value(	
									l_guid, 
									get_account_guid( get_variable('Interest account')), 
									null, 
									l_earliest_transaction_date, 
									l_latest_transaction_date, 
									true);

				-- call log('l_interest=' || ifnull(l_interest, 'NULL'));

				-- keep running total of aggregates
				set l_total_interest 		= ifnull(l_total_interest, 0) 		+ ifnull(l_interest,0);
				set l_total_average_cash_cost 	= ifnull(l_total_average_cash_cost, 0) 	+ ifnull(l_average_cost,0);

				if ifnull(l_interest,0) != 0 then

					-- call log('Writing report line');
					call write_report(	l_bank_report,
								concat(
									if( ifnull(l_account_value,0) = 0,
										concat('<font size=-1><i>', l_account_name, '</i>'),
										l_account_name
									),
									'|',
									if( ifnull(l_interest,0) = 0, '&nbsp;', round(l_interest,2) ),
									'|',
									if( ifnull( l_interest,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_interest * 100) / l_average_cost, 2)
									),
									'|',
									if( ifnull( l_interest,0 ) = 0 or ifnull( l_average_cost,0 ) = 0, 
										'&nbsp;', 
										round( (l_interest * 100) / (l_average_cost * l_years ), 2)
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
		-- call log('l_total_years=' || ifnull(l_total_years, 'NULL'));

		-- call log('1. length(l_asset_report)=' 	|| ifnull(length(l_asset_report),0));
		-- call log('1. length(l_bank_report)=' 	|| ifnull(length(l_bank_report),0));

		-- complete asset report
		if l_asset_report is not null then

			-- call log('Completing asset report');
			-- calculate asset totals
			call write_report(	l_asset_report,
						concat(
							'<b>TOTAL</b>',
							'|',
							if( ifnull(l_total_realised_gains,0) = 0, '&nbsp;', round(l_total_realised_gains,2) ),
							'|',
							if( ifnull( l_total_realised_gains,0 ) = 0 or ifnull( l_total_sold_cost,0 ) = 0, 
								'&nbsp;', 
								round( ( l_total_realised_gains * 100) / l_total_sold_cost, 2)
							),
							'|',
							if( ifnull( l_total_realised_gains,0 ) = 0 or ifnull( l_total_sold_cost,0) = 0, 
								'&nbsp;',
								round( 	(l_total_realised_gains * 100) 
									/ 
									(l_total_sold_cost * l_total_years) 
								, 2)
							),
							'|',
							ifnull( convert( round(l_total_unrealised_gains,2), char), '&nbsp;'),
							'|',
							if( ifnull( l_total_unrealised_gains,0 ) = 0 or ifnull( l_total_remainder_cost,0 ) = 0, 
								'&nbsp;', 
								round( ( l_total_unrealised_gains * 100) / l_total_remainder_cost, 2)
							),
							'|',
							if( ifnull( l_total_unrealised_gains,0 ) = 0 or ifnull( l_total_remainder_cost,0) = 0, 
								'&nbsp;', 
								round( 	(l_total_unrealised_gains * 100) 
									/ 
									(l_total_remainder_cost * l_total_years ) 
								, 2)
							),
							'|', 
							if( ifnull(l_total_dividends,0) = 0, '&nbsp;', round(l_total_dividends,2) ),
							'|',
							if( ifnull( l_total_dividends,0 ) = 0 or ifnull(l_total_average_asset_cost,0 ) = 0, 
								'&nbsp;', 
								round( (l_total_dividends * 100) / l_total_average_asset_cost, 2)
							),
							'|',
							if( ifnull( l_total_dividends,0 ) = 0 or ifnull( l_total_average_asset_cost,0 ) = 0, 
								'&nbsp;', 
								round( 	(l_total_dividends * 100) 
									/ 
									(l_total_average_asset_cost * l_total_years )
								, 2)
							)
						),
						'table-middle');

			-- create stocks table header
			set l_report_header = null;
			call write_report(	l_report_header,
						'Account|Realised gains|Realised gains (% absolute)|Realised gains (% annualised)|Unrealised gains|Unrealised gains (% absolute)|Unrealised gains (% annualised)|Dividends|Dividends (% absolute)|Dividends (% annualised)',
						'table-start');

			-- stick stocks header on in correct place
			set l_asset_report = concat(l_report_header, l_asset_report);

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

		-- call log('2. length(l_asset_report)=' 	|| ifnull(length(l_asset_report),0));
		-- call log('1. length(l_report)=' 	|| ifnull(length(l_report),0));

		-- complete bank report
		if l_bank_report is not null then
			
			-- call log('Completing cash report');
			-- calculate cash totals
			call write_report(	l_bank_report,
						concat(
							'<b>TOTAL</b>',
							'|',
							if( ifnull(l_total_interest,0) = 0, '&nbsp;', round(l_total_interest,2) ),
							'|',
							if( ifnull( l_total_interest,0 ) = 0 or ifnull( l_total_average_cash_cost,0 ) = 0, 
								'&nbsp;', 
								round( l_total_interest * 100 / l_total_average_cash_cost, 2)
							),
							'|',
							if( ifnull( l_total_interest,0 ) = 0 or ifnull( l_total_average_cash_cost,0 ) = 0, 
								'&nbsp;', 
								round(  (l_total_interest * 100)
									/ 
									(l_total_average_cash_cost * l_total_years) 
								, 2)
							)
						),
						'table-middle');

			-- create cash table header
			set l_report_header = null;
			call write_report(	l_report_header,
						'Account|Interest|Interest (% absolute)|Interest (% annualised)',
						'table-start');

			-- stick cash header on in correct place
			set l_bank_report = concat(l_report_header, l_bank_report);

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

		-- call log('2. length(l_bank_report)=' 	|| ifnull(length(l_bank_report),0));
		-- call log('2. length(l_report)=' 	|| ifnull(length(l_report),0));

		-- assemble final complete report and store in variables table
		if l_report is not null then
			
			-- stick on subject line
			call write_report(	l_report, 
						'Account gains report.', 
						'jobname');

			-- delete any previously stored version of this report (which are now out-of-date)
			call delete_series('report_account_gains', concat('1=',p_guid)); 

			-- write completed report to variables table
			-- if variable_exists('report_account_gains(' || p_guid || ',' || p_date1 || ',' || p_date2 || ')') then
			-- 	call put_variable('report_account_gains(' || p_guid || ',' || p_date1 || ',' || p_date2 || ')' , l_report);
			-- else
			call post_variable('report_account_gains(' || p_guid || ',' || p_date1 || ',' || p_date2 || ')' , l_report);
			-- end if;

		end if; -- if l_report is not null

		-- call log('3. length(l_report)=' 	|| ifnull(length(l_report),0));

	end if; -- if not variable_exists('report_account_gains(' || p_guid || ',' || p_date1 || ',' || p_date2 || ')')

	call log('END report_account_gains');
end;
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
	declare l_cash_accounts 		varchar(65000);
	declare l_ISA_accounts 			varchar(2048);
	declare l_tax_year_start 		timestamp;
	declare l_tax_year_end 			timestamp;
	declare l_cash_account_counter 		smallint default 1;
	declare l_ISA_account_counter 		smallint default 1;
	declare l_ISA_allowance_remaining	decimal(8,2);
	
	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
	then
		call log('Report report_remaining_isa_allowance declined to start; Gnucash status = ' || get_variable('Gnucash status') || 'Reporting = ' || get_variable ('Report') );
		leave procedure_block;
	end if;

	-- standardise date
	set p_date = from_days( to_days( ifnull(p_date, current_timestamp) ));
	
	-- dont run this report again if the output still exists
	if not variable_exists('report_remaining_isa_allowance(' || p_date || ')') then

		-- set tax year (within which ISAs run)
		set l_tax_year_start = get_tax_year_end(-1);
		set l_tax_year_end = get_tax_year_end(0);


		-- determine cash accounts whence ISA contributions are made
		set l_cash_accounts = get_account_children( get_account_guid( get_variable( 'Cash account' )), false);

		-- determine ISA accounts whither ISA contributions are sent
		set l_ISA_accounts = concat(
						get_account_children( get_account_guid( get_variable( 'Cash ISA account' )), false),
						',', 
						get_account_children( get_account_guid( get_variable( 'Stocks ISA account' )), false) 
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

		-- return round( get_variable( concat('ISA allowance ', date_format(l_tax_year_end, '%Y') ) ) - l_isa_contribution , 2);
		
		set l_ISA_allowance_remaining = round( get_variable( concat('ISA allowance ', date_format(l_tax_year_end, '%Y') ) ) - l_isa_contribution , 2);

		-- compile report
		if 	l_ISA_allowance_remaining is not null 
			and l_ISA_allowance_remaining > 0 
		then
			call write_report(	l_report, 'ISA allowance report', 'jobname');
			call write_report(	l_report,
							concat(	'Your remaining ISA allowance of GBP', 
									 l_ISA_allowance_remaining, 
									' must be used by ', 
									date_format(get_tax_year_end(0), '%d %M %Y'),
									'.'
									),
							'plain'
							);

			-- delete previous iterations of report (only the latest is relevant)
			call delete_series('report_remaining_isa_allowance', null);

			-- write report to variables table
			call post_variable('report_remaining_isa_allowance(' || p_date || ')' , l_report);

		end if; -- if 	l_ISA_allowance_remaining is not null 
	
	end if; -- if not variable_exists
	
end;
//

-- [R] Breaks down allocation of given account by asset class or location
-- relies entirely on user-defined account attributes such as [asset class=<asset class>], [location=<location>]
drop procedure if exists report_asset_allocation;
//
create procedure report_asset_allocation
	(
		p_guid				varchar(32),
		p_variable			varchar(2048),
		p_date				timestamp
	)
procedure_block : begin
	declare l_total 			decimal(15,2);
	declare l_classification		varchar(50);
	declare l_value				decimal(15,2);
	declare l_proportion			decimal(15,2);
	declare l_report			text;
	declare l_report_header			varchar(500);

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
						get_account_attribute(account_map.guid, p_variable)
				end,
				'UNKNOWN'
			),
			round(
				sum(
					get_account_value(
						account_map.guid, 
						get_default_currency_guid(), 
						null,
						p_date, 
						false)
				)
			,2)
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

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
	then
		call log('Report report_asset_allocation declined to start; Gnucash status = ' || get_variable('Gnucash status') || 'Reporting = ' || get_variable ('Report') );
		leave procedure_block;
	end if;
	
	set p_guid = ifnull(p_guid, get_account_guid('Assets'));
	set p_variable = ifnull(p_variable, 'TYPE');
	set p_date = round_timestamp(ifnull(p_date, current_timestamp));
	set l_total = get_account_value( p_guid, null, null, p_date, true);

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

		set l_proportion = round(l_value * 100 / l_total, 2);

		call write_report(	l_report,
					concat(
						l_classification,
						'|',
						l_value,
						'|',
						l_proportion,
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
		call write_report(	l_report_header,
					concat(
						'Classification|',
						get_variable('Default currency'),
						'|Allocation (%)|Allocation (graphical)'
						),
					'table-start');

		-- stick header on in correct place
		set l_report = concat(l_report_header, l_report);

		-- add in total line
		call write_report(	l_report,
					concat(
						'<b>TOTAL</b>|',
						round(l_total, 2),
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
					concat(	' asset allocation report, by ',
						p_variable
						), 
					'jobname');

		-- delete previous iterations of report (only the latest is relevant)
		call delete_series('report_asset_allocations', concat('1=', p_guid , ',2=', p_variable));

		-- write completed report to variables table
		-- if variable_exists('report_asset_allocations(' || p_guid || ',' || p_variable || ',' || p_date || ')') then
		-- 	call put_variable('report_asset_allocations(' || p_guid || ',' || p_variable || ',' || p_date || ')' , l_report);
		-- else
			call post_variable('report_asset_allocations(' || p_guid || ',' || p_variable || ',' || p_date || ')' , l_report);
		-- end if;

	end if;

end;
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
		p_index	tinyint
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

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
	then
		call log('Report report_uk_tax declined to start; Gnucash status = ' || get_variable('Gnucash status') || 'Reporting = ' || get_variable ('Report') );
		leave procedure_block;
	end if;

	-- set defaults
	set p_index = ifnull(p_index, -1);

	-- set tax dates
	set l_tax_year_start = get_tax_year_end(p_index - 1);
	set l_tax_year_end = get_tax_year_end(p_index);

	-- report table
	drop temporary table if exists report;
	create temporary table report 
	(
		id				smallint not null auto_increment,
		name			varchar(2048),
		gross_of_tax	decimal(20,6),
		net_of_tax		decimal(20,6),
		tax_paid		decimal(20,6),
		primary key(id)
	);

	-- set account values
	set l_taxable_taxed_salary = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable and taxed salary account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_taxable_untaxed_salary = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable and untaxed salary account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_taxable_taxed_interest = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable and taxed interest account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_taxable_untaxed_interest = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable and untaxed interest account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_taxable_dividends = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable dividends account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_taxable_capital_gains = - (round(
								get_account_value(
								get_account_guid(get_variable('Taxable capital gains account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));
	set l_inheritance = - (round(
								get_account_value(
								get_account_guid(get_variable('Inheritance account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2));

	set l_interest_income_tax_paid = round(
								get_account_value(
								get_account_guid(get_variable('Income tax (interest) paid account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2);
	set l_salary_income_tax_paid = round(
								get_account_value(
								get_account_guid(get_variable('Income tax (salary) paid account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2);
/*
	set l_national_insurance_paid = round(
								get_account_value(
								get_account_guid(get_variable('National insurance paid account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2);
*/
	set l_tax_rebates = round(
								get_account_value(
								get_account_guid(get_variable('Income tax rebates account')),
								null,
								l_tax_year_start,
								l_tax_year_end,
								true
							),2);

	-- the following are paid in the tax year *after* the one being specified
	set l_capital_gains_tax_paid = - round(
								get_account_value(
								get_account_guid(get_variable('Capital gains tax paid account')),
								null,
								null,
								null,
								true
							),2);

	set l_self_assessment_tax_paid = - round(
								get_account_value(
								get_account_guid(get_variable('Self assessment tax paid account')),
								null,
								null,
								null,
								true
							),2);

	-- not sure when this one is paid
	set l_inheritance_tax_paid = - round(
								get_account_value(
								get_account_guid(get_variable('Inheritance tax paid account')),
								null,
								null,
								null,
								true
							),2);

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

/*
	-- personal allowance (nil tax rate band) reduces by £1 for every £2 income over the personal allowance limit
	if l_gross_income > get_variable( 'Income tax nil rate band income limit' ) then
		set l_personal_allowance = get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y')))
									- (l_gross_income - get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y') ) ) )/2;
	else
		set l_personal_allowance = get_variable( concat( 'Income tax nil rate band ', date_format(l_tax_year_end, '%Y')));
	end if;

	-- call log (concat('l_gross_salary=',l_gross_salary));
	-- call log (concat('l_personal_allowance=',l_personal_allowance));
	-- call log (concat('income tax lower rate=', get_variable('Income tax lower rate')));
	-- call log (concat('income tax basic band=', get_variable( concat( 'Income tax lower rate band ', date_format(l_tax_year_end, '%Y'))) ));
	
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

	-- set report name
	/*
	set l_report_name = concat( 'UK self assessment tax report ', 
								date_format(l_tax_year_start, '%Y'), 
								'/', 
								date_format(l_tax_year_end, '%Y')
						);
	*/

	insert into report 
	(
		name,
		gross_of_tax,
		net_of_tax,
		tax_paid
	)
	values
	(
		'Salary taxed at source',
		l_taxable_taxed_salary,
		l_taxable_taxed_salary - l_salary_income_tax_paid,
		l_salary_income_tax_paid
	),
	(
		'Salary untaxed at source',
		l_taxable_untaxed_salary,
		null,
		null
	),
	(
		'Total salary',
		l_gross_salary,
		null,
		l_salary_income_tax_paid
	),
	(
		'Interest taxed at source',
		l_taxable_taxed_interest,
		l_taxable_taxed_interest - l_interest_income_tax_paid,
		l_interest_income_tax_paid
	),
	(
		'Interest untaxed at source',
		l_taxable_untaxed_interest,
		null,
		null
	),
	(
		'Total interest',
		l_gross_savings,
		null,
		l_interest_income_tax_paid
	),
	(
		'Dividends taxed at 10% at source',
		l_taxable_dividends + l_dividends_income_tax_paid,
		l_taxable_dividends,
		l_dividends_income_tax_paid
	),
	(
		'Capital gains (or losses)',
		l_taxable_capital_gains,
		null,
		l_capital_gains_tax_paid
	),
	(
		'Inheritance',
		l_inheritance,
		null,
		l_inheritance_tax_paid
	),
	(
		'Self-assessment',
		null,
		null,
		l_self_assessment_tax_paid
	),
	(
		'Tax rebates',
		null,
		null,
		l_tax_rebates
	),
	(
		'Total',
		l_gross_income,
		null,
		l_total_tax_paid
	)
	;

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
	-- update or post report
/*
	if variable_exists( l_report_name ) and get_variable( l_report_name ) != l_report then
		call put_variable(l_report_name, l_report);
	else
		call post_variable(l_report_name, l_report);
	end if;
*/
	-- print report
	select
			if ( locate('TOTAL', upper(name)) != 0, concat('<i>', name, '</i>'), name) as "Name",
			if ( locate('TOTAL', upper(name)) != 0, concat('<i>', ifnull( round( gross_of_tax,	2), '&nbsp;'), '</i>'), ifnull( round( gross_of_tax,	2), '&nbsp;') ) as "Gross of tax",
			if ( locate('TOTAL', upper(name)) != 0, concat('<i>', ifnull( round( net_of_tax,	2), '&nbsp;'), '</i>'), ifnull( round( net_of_tax,	2), '&nbsp;') ) as "Net of tax",
			if ( locate('TOTAL', upper(name)) != 0, concat('<i>', ifnull( round( tax_paid, 		2), '&nbsp;'), '</i>'), ifnull( round( tax_paid,		2), '&nbsp;') ) as "Tax paid"
	from
			report
	where 	
			ifnull(gross_of_tax,0) 	!= 0
			or ifnull(net_of_tax,0)	!= 0
			or ifnull(tax_paid,0) 	!= 0
	order by 
			id;

end;
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
	
	-- the sensitivity of the test is entirely a matter of personal preference (range 1-00 with 1 being most sensitive)
	-- and is set via : call 
	declare l_performance_sensitivity		tinyint default 0; 

	declare	l_account_guid				varchar(32);
	declare	l_commodity_guid			varchar(32);
	declare l_account_total				decimal(20,6) default 0;
	declare l_target_total				decimal(20,6) default 0;
	declare l_report				text;
	declare l_report_header				varchar(500);
	declare l_recommendation			varchar(500);

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

	declare	l_performance_signal			tinyint;
	declare l_macd_signal				varchar(50);

	declare l_account_list_done 			boolean default false;
	declare l_account_list_done_temp 		boolean default false;

	declare lc_account_list cursor for
		select distinct 
			guid,
			get_account_commodity(guid)
		from
			account_map
		where
			get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
			and not is_hidden(guid)
			and not is_parent(guid)
			and is_child(guid);

	declare continue handler for not found set l_account_list_done =  true;

	-- call log('START report_target_allocations');

	-- Dont proceed if GnuCash DB is  unreadable or reports have been explicitly turned off 
	if  get_variable('Gnucash status') not like 'R%' 
		or get_variable ('Report') != 'Y'
	then
		call log('Report report_target_allocations declined to start; Gnucash status = ' || get_variable('Gnucash status') || 'Reporting = ' || get_variable ('Report') );
		leave procedure_block;
	end if;

	-- get current total value for parent account
	-- set l_account_total = get_account_value(p_guid, get_default_currency_guid(), null, null, true);

	select 	sum( get_account_value(guid, get_default_currency_guid(), null, null, false) )
	into 	l_account_total
	from
		account_map
	where
		get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
		and not is_hidden(guid)
		and not is_parent(guid)
		and is_child(guid);

	-- get sum of targets for parent account (which cant be assumed to be 100)
	select 	sum( ifnull( get_account_attribute(guid, 'target' ), 0) )
	into 	l_target_total
	from
		account_map
	where
		get_account_parents(guid, true) regexp concat( '[[:<:]]', p_guid, '[[:>:]]' )
		and not is_hidden(guid)
		and not is_parent(guid)
		and is_child(guid);

	-- loop through each account to be assessed
	open lc_account_list;	
	set l_account_list_done = false;

	account_list_loop : loop
		
		fetch lc_account_list 
		into l_account_guid, l_commodity_guid;

		if l_account_list_done then 
			leave account_list_loop;
		else
			set l_account_list_done_temp = l_account_list_done;
		end if;

		set l_current_total_value = get_account_value( l_account_guid, get_default_currency_guid(), null, null, null);
		set l_current_unit_value_native_currency = get_commodity_value( l_commodity_guid, null);
		set l_target_allocation = ifnull( get_account_attribute(l_account_guid,'target'), 0) * 100 / l_target_total;

		set l_current_allocation = l_current_total_value * 100 / l_account_total;
		set l_target_total_value = l_target_allocation * l_account_total / 100 ;
		set l_current_unit_value_default_currency =
				convert_value( 
					l_current_unit_value_native_currency, 
					get_commodity_currency(l_commodity_guid), 
					get_default_currency_guid(), 
					null);

		set l_target_unit_change = (l_target_total_value - l_current_total_value) / l_current_unit_value_default_currency ;

		-- averaged estimate predicted gain or loss on a sale (Asset, Stocks only)
		-- and original unit cost, for comparison with proposed purchases
		if 	get_account_type(l_account_guid) in ('ASSET', 'STOCK') then

			-- only attempt to work out original cost if the holding has ever been purchased
			if is_used(l_account_guid) 
			then

				call get_account_costs(l_account_guid, null, null, l_remainder_cost, l_sold_cost, l_average_cost);	
				set l_original_unit_value_default_currency = l_remainder_cost / get_account_units( l_account_guid, null, null) ;

				if l_target_unit_change < 0 then

					set l_predicted_gain = 
						( abs(l_target_unit_change) * l_current_unit_value_default_currency ) -- current value of l_target_unit_change units
						-
						( abs(l_target_unit_change) * l_original_unit_value_default_currency ); -- initial (average) cost of l_target_unit_change units

				else

					set l_predicted_gain = 0;

				end if;
			end if;

			set l_recommendation = null;

			-- compile report
			if abs( l_target_total_value - l_current_total_value) > get_variable('Trivial value') then
	
				if p_mode = 'report' then

					set l_recommendation = concat(
									if( l_target_unit_change < 0, 'SELL ', 'BUY '),
									floor( abs( l_target_unit_change )),
									' units at ',
									get_commodity_mnemonic( get_account_currency( l_account_guid ) ) ,
									round(l_current_unit_value_default_currency,2) ,
									' for a total of ',
									get_variable('Default currency') ,
									floor( abs( l_target_total_value - l_current_total_value))
								);
					
					if is_used(l_guid) then
						
							set l_recommendation = concat(l_recommendation,
												if( l_target_unit_change < 0,
													concat(
														'</br>Predicted ',
														if(ifnull(l_predicted_gain,0) < 0, 'loss ', 'gain '), 
														get_variable('Default currency'), 
														floor(abs(ifnull(l_predicted_gain,0)))
														),
													''),
												if( l_target_unit_change > 0,
													concat(
														'</br>New unit price is ', 
														round( abs( l_current_unit_value_default_currency - l_original_unit_value_default_currency) * 100 / l_original_unit_value_default_currency, 0),
														'% ',
														if(l_current_unit_value_default_currency > l_original_unit_value_default_currency, 'higher ', 'lower '),
														'than average purchase price.'
														),
														'')
												);
					end if; -- if is_used(l_guid) 

					call write_report(	l_report,
									concat(
										get_account_short_name(l_account_guid),
										'|',
										ifnull( round( l_current_total_value), '&nbsp;'),
										'|',
										ifnull( floor( l_current_allocation), '&nbsp;'),
										'|',
										ifnull( floor( l_target_allocation), '&nbsp;'),
										'|',
										ifnull(l_recommendation, '&nbsp;')
									),
									'table-middle'
								);

				elseif  p_mode = 'alert' then

					set p_mode = ifnull(p_mode,'report');
					if variable_exists('Performance sensitivity') then
						set l_performance_sensitivity = get_variable('Performance sensitivity');
					end if;

					set l_performance_signal = get_performance_signal( l_commodity_guid );
					set l_macd_signal = get_macd_signal( l_commodity_guid, null);

					-- only return accounts that require immediate attention
					if	l_target_unit_change < 0 then
			
						if l_performance_signal < - abs(l_performance_sensitivity) then
			
							set l_recommendation = concat( 
											if(l_recommendation is not null,
												concat(l_recommendation, '</br>'),
												''),
											'Performance signal (',
											 l_performance_signal,
											') suggests ',
											if( abs(l_performance_signal) <= 8,
												'WEAK',
												'STRONG'),
											' SELL');
						end if;
						if locate('SELL', l_macd_signal) != 0 then
			
							set l_recommendation = concat(
											if(l_recommendation is not null,
												concat(l_recommendation, '</br>'),
												''),
											'MACD signal :',
											 l_macd_signal);
						end if;

					elseif l_target_unit_change > 0 then

						if l_performance_signal > abs(l_performance_sensitivity) then
	
							set l_recommendation = concat( 
											if(l_recommendation is not null,
												concat(l_recommendation, '</br>'),
												''),
											'Performance signal (',
											 l_performance_signal,
											') suggests ',
											if( abs(l_performance_signal) <= 8,
												'WEAK',
												'STRONG'),
											' BUY');
						end if;
						if locate('BUY', l_macd_signal) != 0 then
	
							set l_recommendation = concat(
											if(l_recommendation is not null,
												concat(l_recommendation, '</br>'),
												''),
											'MACD signal :',
											 l_macd_signal);
						end if;

					end if;

					-- call log('l_recommendation=' || l_recommendation );

					if l_recommendation is not null then

						call write_report(	l_report,
									concat(
										get_account_short_name(l_account_guid),
										'|',
										ifnull( round( l_current_total_value), '&nbsp;'),
										'|',
										ifnull( floor( l_current_allocation), '&nbsp;'),
										'|',
										ifnull( floor( l_target_allocation), '&nbsp;'),
										'|',
										ifnull(l_recommendation, '&nbsp;')
									),
									'table-middle'
								);

					end if; -- if abs(performance_signal) > 5

				end if; -- if p_mode = 'report'

			end if; -- if abs( target_total_value - current_total_value) > get_variable('Trivial value')

		end if; -- if is_used(l_guid) 

		set l_account_list_done = l_account_list_done_temp;

	end loop;

	close lc_account_list;	

	if l_report is not null then

		-- create table header
		call write_report(	l_report_header,
					'Holding|Value|Current allocation (%)|Target allocation (%)|Recommendation',
					'table-start');

		-- stick header on in correct place
		set l_report = concat(l_report_header, l_report);

		-- complete report
		call write_report(	l_report,
					null,
					'table-end');

		-- stick on subject line
		call write_report(	l_report, 
					concat('Target allocation ', p_mode, ' for "', get_account_short_name(p_guid) , '" account.'), 
					'jobname');

		-- delete previous iterations of report (only the latest is relevant)
		call delete_series('report_target_allocations', concat('1=', p_guid , ',2=', p_mode));

		-- write completed report to variables table
		-- if variable_exists('report_target_allocations(' || p_guid || ',' || p_mode || ')') then
		-- 	call put_variable('report_target_allocations(' || p_guid || ',' || p_mode || ')' , l_report);
		-- else
			call post_variable('report_target_allocations(' || p_guid || ',' || p_mode || ')' , l_report);
		-- end if;

	end if;

	-- call log('END report_target_allocations');
end;
//

-- [D.1] Database update routines
-- All custom GnuCash routines that *alter* the GnuCash database are listed here
-- If you want *no chance* of these running, then don't allow the customgnucash user write-access to gnucash tables

-- [RW] locks Gnucash database for CustomGnucash use, if possible
-- returns true on success, false on failure
-- this will cause the GnuCash application to warn about being unable to obtain database locks (which can be overidden by the GUI user with unpredictable results)
drop function if exists gnc_lock;
//
create function gnc_lock()
	returns boolean
begin
	declare l_lock 		boolean default false;
	declare l_lock_count	tinyint;

	-- Dont proceed if GnuCash GUI has locked the DB or the DB is tested as unwriteable
	if is_locked() or get_variable('Gnucash status') != 'RW' then
		call log('Gnucash DB is either already locked or is not writeable');
		return l_lock;
	end if;

	-- The Gnucash GUI may not have locked the DB, but CustomGnucash itself may have done
	select 	count(*)
	into 	l_lock_count
	from 	gnclock;

	if l_lock_count = 0 then
		insert into gnclock
		values(
			session_user(),
			connection_id()
		);
	end if;

	-- check that lock has been created
	select 	if(count(*)>0, true, false)
	into 	l_lock
	from 	gnclock 
	where 	hostname = session_user();

	return l_lock;
end;
//

-- [RW] unlocks Gnucash database from CustomGnucash use
-- means that GnuCash application wont complain about this database lock on startup
drop procedure if exists gnc_unlock;
//
create procedure gnc_unlock()
procedure_block:begin

	-- Dont proceed if GnuCash DB is tested as unwriteable
	if get_variable('Gnucash status') != 'RW' then
		call log('Gnucash DB is not writeable');
		leave procedure_block;
	end if;

	start transaction;
	delete 
	from 	gnclock
	where 	hostname = session_user();
	commit;

end;
//

-- [RW] Adds a new commodity price to the commodity table
-- if its sane, and hasn't already been added
-- designed to be called from an OS scheduler using gnc-fq-dump to obtain quotes :
drop procedure if exists post_commodity_price;
//
create procedure post_commodity_price
	(
		p_symbol		varchar(10),
		p_date			varchar(10),
		p_currency		varchar(5),
		p_last			decimal(20,6),
		p_source		varchar(255)
	)
procedure_block : begin
	declare l_previous_price 	decimal(20,6);
	declare l_previous_date		timestamp;
	declare l_previous_denom 	bigint(20);
	declare l_previous_currency 	varchar(32);

	-- Dont proceed if GnuCash DB cannot be locked
	if not gnc_lock() then
	call log('Procedure post_commodity_price : Unable to lock GnuCash DB.');
		leave procedure_block;
	end if;
	
	if commodity_exists(trim(p_symbol)) then
		
		-- set defaults
		set l_previous_price 	= get_commodity_value( get_commodity_guid( trim( p_symbol )), null);
		set l_previous_date 	= get_commodity_latest_date( get_commodity_guid( trim( p_symbol )));
		set l_previous_denom 	= get_commodity_latest_denom( get_commodity_guid( trim( p_symbol )));
		set l_previous_currency = get_commodity_currency( get_commodity_guid( trim( p_symbol )));

		-- gnc-fq-dump (or yahoo) has the occasional tendency to report the prices a factor of 100 out
		if 	abs(p_last - l_previous_price) / l_previous_price >= 0.95 then
			if p_last > l_previous_price then
				set p_last = p_last / 100;
			else
				set p_last = p_last * 100;
			end if;
		end if;

		-- if values appear sane, and are different from the previous, then insert them
		if 	l_previous_price is null -- this is the first quote
			or 
			(
				l_previous_currency = get_commodity_guid(trim(p_currency)) -- currency must be the same
				and str_to_date(p_date, '%m/%d/%Y') > l_previous_date -- new value must be newer than old value
				and abs(p_last - l_previous_price) / l_previous_price <= 0.85 -- *dont* insert new value if its more than 85% different from previous value
				and p_last != l_previous_price -- new value must be different from old value
			)
			then

			start transaction;
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
				get_commodity_guid(trim(p_symbol)),
				ifnull(get_commodity_currency(get_commodity_guid(trim(p_symbol))), get_commodity_guid(trim(p_currency))),
				str_to_date(p_date, '%m/%d/%Y'),
				ifnull(p_source, 'Finance::Quote'),
				'last',
				p_last * ifnull(l_previous_denom, 1000000),	-- quotes for previously unquoted commodities have no denom, so assume max for decimal(20,6) type
				ifnull(l_previous_denom, 1000000)		
			);

			commit;

			-- log action
			call log('Inserted new price ' || p_currency || convert(p_last, char) || ' for ' || if( is_currency( get_commodity_guid(trim(p_symbol)) ) , 'currency ', 'commodity ') || trim(p_symbol) );

		end if;

	end if;

	-- unlock database
	call gnc_unlock();
end;
//

-- [RW] posts a split (part of a transaction) (dangerous!)
-- if p_transaction_guid is specified, adds split to existing transaction
-- otherwise, adds a new transaction
drop procedure if exists post_split;
//
create procedure post_split
	(
		p_account_from		varchar(32),
		p_account_to		varchar(32),
		p_value			decimal(20,6),
		p_transaction_guid	varchar(32),
		p_date_posted		timestamp,
		p_description		varchar(2048)
	)
procedure_block : begin
	declare l_exists		tinyint default 0;
	declare l_guid			varchar(32);
	declare l_default_currency	varchar(32);
	declare l_value_denom		bigint(20);
	declare l_value_num		bigint(20);
	declare l_quantity_denom_from	bigint(20);
	declare l_quantity_num_from 	bigint(20);
	declare l_quantity_denom_to	bigint(20);
	declare l_quantity_num_to 	bigint(20); 
	
	-- Dont proceed if GnuCash DB cannot be locked
	if not gnc_lock() then
		call log('Procedure post_split : Unable to lock GnuCash DB.');
		leave procedure_block;
	end if;

	-- verify inputs are sane 
	if 	p_date_posted is null 
		or p_date_posted > current_timestamp 
		or p_account_from is null
		or p_account_to is null
		or p_account_from = p_account_to
	then
		call log('Post split aborted. p_date_posted=' || p_date_posted || ', p_account_from=' || p_account_from || ', p_account_to=' || p_account_to ); 
		leave procedure_block;
	end if;

	-- verify inputs are sane [2]
	select 	count(*)
	into 	l_exists
	from	accounts
	where	guid in (p_account_from, p_account_to);

	if l_exists != 2 then
		call log('Post split aborted. Accounts ' || p_account_from || ' or ' || p_account_to || ' could not be found.');
		leave procedure_block;
	end if;

	if p_transaction_guid is not null then

		set l_exists = 0;

		select 	count(*)
		into 	l_exists
		from	transactions
		where	guid = p_transaction_guid;

		if l_exists != 1 then
			leave procedure_block;
		end if;

	end if;

	-- calculate values beforehand so all inserts are as quick as possible
	set l_default_currency = get_default_currency_guid();
	set l_value_denom = get_commodity_latest_denom( l_default_currency );
	set l_value_num = p_value * l_value_denom;

	-- when posting capital gains from a STOCK/ASSET account then the quantity for the STOCK/ASSET account is 0
	if 	get_account_type( p_account_to ) in ('ASSET','STOCK') 
		and is_child_of( p_account_from, get_account_guid(get_variable( 'Capital gains account' )),true)
	then
		set l_quantity_denom_to = 1;
		set l_quantity_num_to = 0;
	else 
		set l_quantity_denom_to = get_commodity_latest_denom( get_account_commodity( p_account_to ));
		set l_quantity_num_to = convert_value(p_value, l_default_currency, get_account_commodity( p_account_to ), p_date_posted ) * l_quantity_denom_to; 
	end if;

	if 	get_account_type( p_account_from ) in ('ASSET','STOCK') 
		and is_child_of( p_account_to, get_account_guid(get_variable( 'Capital gains account' )),true)
	then
		set l_quantity_denom_from = 1;
		set l_quantity_num_from = 0;
	else 
		set l_quantity_denom_from = get_commodity_latest_denom( get_account_commodity( p_account_from ));
		set l_quantity_num_from = convert_value(p_value, l_default_currency, get_account_commodity( p_account_from ), p_date_posted ) * l_quantity_denom_from; 
	end if;

	-- the subsequent insert statements are either *all* committed or *none* are committed
	start transaction;

	-- add a transaction if required
	if p_transaction_guid is null then
		
		set p_transaction_guid = new_guid();

		insert into transactions 
			(guid, currency_guid, post_date, enter_date, description)
		values
			(	p_transaction_guid, 
				l_default_currency, 
				p_date_posted, 
				current_timestamp, 
				ifnull(p_description, 'Transaction added by customgnucash.post_split')
			);
		call log('Added transaction ' || p_transaction_guid );

	end if;

	-- always add 2 splits, one for each side of the transaction
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
			lot_guid)
	values
		(	l_guid, 
			p_transaction_guid, 
			p_account_from,
			ifnull(p_description, 'Split added by customgnucash.post_split'),
			'n', 
			null,
			- l_value_num,
			l_value_denom,
			- l_quantity_num_from,
			l_quantity_denom_from,
			null
		);
	call log('Added split ' || l_guid || ' to transaction ' || p_transaction_guid );

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
			lot_guid)
	values
		(	l_guid, 
			p_transaction_guid, 
			p_account_to, 
			ifnull(p_description, 'Split added by customgnucash.post_split'),
			'n', 
			null,
			l_value_num,
			l_value_denom,
			l_quantity_num_to,
			l_quantity_denom_to,
			null
		);
	call log('Added split ' || l_guid || ' to transaction ' || p_transaction_guid );

	-- end transaction
	commit;

	-- unlock database
	call gnc_unlock();
end;
//

-- [RW] calculates (and adds splits, if required) for realised capital gains for specified account
-- uses HMRC rules regarding capital gains calculations; when shares are indistinguishable, earlier bought shares are presumed to be sold first
-- does nothing if a (sale) transaction already has a capital gain posted (even if its wrong - so a manual entry made through the GnuCash client is not overwritten by this automatic one)
-- only affects accounts of ASSET or STOCK type
-- manages stock splits (consolidations) if splits are added to GnuCash through the splits tool (which flags them with 'Split' in the action field)
-- doesn't manage accounts without a unit price; (like some mutual or pension funds, or real estate) 
drop procedure if exists post_gain;
//
create procedure post_gain
	(
		p_guid				varchar(32)
	)			
procedure_block : begin
	declare l_realised_gain 		decimal(20,6) default 0;
	declare l_capital_gains_guid		varchar(32);
	declare l_stock_split_ratio		decimal(20,6);

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
			-- join gnucash.accounts
				-- on splits.account_guid = accounts.guid
		where
			splits.quantity_num != 0
			and get_account_type( splits.account_guid ) in ('ASSET', 'STOCK', 'EXPENSE')
		group by 1,2
		order by
			transactions.post_date,
			transactions.enter_date;

	declare continue handler for not found set l_transactions_done =  true;

	-- Dont proceed if GnuCash DB cannot be locked
	-- just a belt-n-braces check as it is also checked by calling procedure post_all_gains
	if not gnc_lock() then
	call log('Procedure post_gain : Unable to lock GnuCash DB.');
		leave procedure_block;
	end if;

	-- calculate gains on STOCK or ASSET account types only
	-- ? exclude accounts for which cap gains cannot be calced; accounts denominated in home currency (where there is no independent unit value)
	if get_account_type(p_guid) in ('STOCK', 'ASSET') 
	then

			-- find out where the capital gains are posted for this account
			set l_capital_gains_guid = get_account_guid( get_account_attribute(p_guid, 'Capital gains') );

			-- the DB retrieval routines get_account_guid & get_account_attribute set l_transactions_done to true
			set l_transactions_done =  false;

			-- bail if no capital gains account found
			if l_capital_gains_guid is null then
				leave procedure_block;
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
			set	 l_transactions_done = false;

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

							-- only log the capital gains if a capital gains has not already been posted, and this transaction is not a share-split (ie share offer or consolidation)
							if not split_exists(l_transaction_guid, l_capital_gains_guid, p_guid) 
								and locate('SPLIT', l_action) = 0 
								then

								-- call log('call post_split( ''' || l_capital_gains_guid ||''','''|| p_guid ||''','|| l_realised_gain ||','''|| l_transaction_guid ||''', str_to_date('''|| l_post_date ||''', ''%Y-%m-%d %H:%i:%S''),'|| '''Capital gains calculated by customgnucash.post_gains'')' );
								call post_split( l_capital_gains_guid, p_guid, round(l_realised_gain,6), l_transaction_guid, l_post_date, 'Capital ' || if( l_realised_gain < 0, 'loss', 'gain') || ' calculated by customgnucash.post_gains');
							
							end if;

						end; -- tally block					
					end if; -- if locate('SPLIT', l_action) != 0
				end if; -- if l_total_quantity > 0

				-- set  l_transactions_done back to what it was before so that outer loop can continue
				set  l_transactions_done =  l_transactions_done_temp;

			end loop; -- transaction_loop

		-- for debugging only
		-- select * from tally;

		close lc_transaction;	
	end if; -- if get_account_type(p_guid) in ...

	-- dont unlock gnucash db as this procedure is called repeatedly by post_all_gains
	-- call gnc_unlock()

end; -- outer block
//

-- [RW] calculates (and adds) realised capital gains for *all* applicable asset accounts
-- specifically excludes accounts denominated in the default currency; gains can only be calculated on acounts denominated in units (eg stock, currency) the value of which can change wrt default currency
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
			and get_account_commodity(guid) != get_default_currency_guid();
			-- and get_account_attribute(guid, 'ASSET CLASS') not in ('MUTUAL FUND', 'PROPERTY')
	declare continue handler for not found set l_asset_account_done =  true;
	
	-- Dont proceed if GnuCash DB cannot be locked
	if not gnc_lock() then
		call log('Procedure post_all_gains : Unable to lock GnuCash DB.');
		leave procedure_block;
	end if;

	open lc_asset_account;	
	set l_asset_account_done = false;
	
	asset_account_loop : loop
	
		fetch lc_asset_account into l_guid;
	
		if l_asset_account_done then 
			leave asset_account_loop;
		else
			set l_asset_account_done_temp = l_asset_account_done;
		end if;
		
		call post_gain(l_guid);
		set l_asset_account_done = l_asset_account_done_temp;

	end loop;

	close lc_asset_account;	

	-- unlock database
	call gnc_unlock();
end;
//

-- [RW] Cleans up prices table, which may contain duplicates
drop procedure if exists clean_prices;
//
create procedure clean_prices()
procedure_block : begin
	declare l_commodity_guid		varchar(32);
	declare l_currency_guid			varchar(32);
	declare l_date				timestamp;
	declare l_value				decimal(20,2);
	declare l_duplicate_price_done 		boolean default false;
	declare l_duplicate_price_done_temp 	boolean default false;

	declare lc_duplicate_price cursor for
		select distinct
			commodity_guid,
			currency_guid,
			round_timestamp(date),
			round(value_num/value_denom,2)
		from 	prices
		where 	type = 'last'
			and source = 'Finance::Quote'
		group by
			commodity_guid,
			currency_guid,
			round_timestamp(date),
			round(value_num/value_denom,2)
		having count(*) >1;
	declare continue handler for not found set l_duplicate_price_done =  true;

	-- Dont proceed if GnuCash DB cannot be locked
	if not gnc_lock() then
	call log('Procedure clean_prices : Unable to lock GnuCash DB.');
		leave procedure_block;
	end if;
	
	open lc_duplicate_price;	
	set l_duplicate_price_done = false;
	
		duplicate_price_loop : loop
		
		fetch lc_duplicate_price 
		into l_commodity_guid, l_currency_guid, l_date, l_value;
	
		if l_duplicate_price_done then 
			leave duplicate_price_loop;
		else
			set l_duplicate_price_done_temp = l_duplicate_price_done;
		end if;

		start transaction;
		
		-- delete *all* matching values
		delete from prices
		where
			commodity_guid = l_commodity_guid
			and currency_guid = l_currency_guid
			and round_timestamp(date) = l_date
			and round(value_num/value_denom,2) = l_value;

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
			'Finance::Quote',
			'last',
			l_value * 1000000,
			1000000
		);

		commit;
			
		set l_duplicate_price_done = l_duplicate_price_done_temp;

	end loop;

	close lc_duplicate_price;	

	-- optimize table (recreate indices, gaps in data etc)
	-- optimize table prices;
		
	-- unlock database
	call gnc_unlock();

end;
//

-- [E.1] System status and self-testing routines
drop procedure if exists customgnucash_status;
//
create procedure customgnucash_status()
procedure_block : begin
	declare l_report 	text;
	declare l_integer1	int;
	declare l_integer2	int;
	declare l_text		varchar(500);

	-- mark status as undefined
	call delete_variable('CustomGnucash status');

	-- declare error handlers

	-- Check version of MySQL / MariaDB is supported

	-- Check expected number of tables
	select 	count( distinct table_name)
	into 	l_integer1
	from 	information_schema.tables
	where 	table_schema = schema()
	and	table_type = 'BASE TABLE'
	and 	table_name in ('variable', 'log');

	if l_integer1 != 2 then
		call write_report(l_report, 'Expected 2 tables ("variable" and "log"), but found ' || l_integer1, 'plain');
	end if;

	-- Check expected number of views
	-- select 	count( distinct table_name)
	-- into 	l_integer1
	-- from 	information_schema.views
	-- where 	table_schema = schema();

	-- if l_integer1 != 25 then
	-- 	call write_report(l_report, 'Expected 25 views, found ' || l_integer1, 'plain');
	-- end if;

	-- check a few of the critical views
	select count( distinct table_name)
	into 	l_integer1
	from 	information_schema.views
	where 	table_schema = schema()
	and 	table_name in ('accounts','commodities','gnclock','prices','splits','transactions','versions');

	if l_integer1 != 7 then
		call write_report(l_report, 'A critical view ("accounts", "commodities", "gnclock", "prices", "splits", "transactions" or "versions") was not found.', 'plain');
	end if;

	-- Check expected number of customgnucash procedures
	select 	count( distinct specific_name)
	into 	l_integer1
	from 	information_schema.routines
	where 	routine_schema = schema()
	and 	routine_type = 'PROCEDURE';

	if l_integer1 != 24 then
		call write_report(l_report, 'Expected 24 procedures, found ' || l_integer1, 'plain');
	end if;

	-- Check expected number of customgnucash functions
	select 	count( distinct specific_name)
	into 	l_integer1
	from 	information_schema.routines
	where 	routine_schema = schema()
	and 	routine_type = 'FUNCTION';

	if l_integer1 != 52 then
		call write_report(l_report, 'Expected 52 functions, found ' || l_integer1, 'plain');
	end if;

	-- Test variable logging routines
	select 	count(*)
	into 	l_integer1
	from 	variable;

	call post_variable('customgnucash_status', 'test');

	select 	count(*)
	into 	l_integer2
	from 	variable;

	if not (variable_exists('customgnucash_status')
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

	if not (variable_exists('customgnucash_status')
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

	if 	variable_exists('customgnucash_status')
		or l_integer1 != l_integer2
	then
		call write_report(l_report, 'Failed to delete a variable to the customgnucash variables table.', 'plain');
	end if;

	-- Test DIY array management routines
	set l_text = 'H,Q,Z,P,Z,C';
	call put_element(l_text, 'A', ',');

	if not	(get_element( sort_array(l_text, ',', null), 1, ',') = 'A'
		and get_element_count( l_text, ',') = 7
		and get_element_count( sort_array(l_text, ',', 'u'), ',') = 6
		)
	then
		call write_report(l_report, 'Array manipluation routines returned unexpected result.', 'plain');
	end if;

	-- Test standalone misc routines
	if length(new_guid()) != 32 then
		call write_report(l_report, 'Function new_guid did not return a string of 32 chars', 'plain');
	end if;

	if html_bar(1,null) != '<table class=html_bar bgcolor=black><tr><td>&nbsp;</td></tr></table>' then
		call write_report(l_report, 'Function html_bar did not return the expected string.', 'plain');
	end if;

	-- Test commodity management routines
	if not (commodity_exists(get_variable('Default currency'))
		and is_currency(get_default_currency_guid())
		and get_commodity_value(get_default_currency_guid(),null) = 1
		and get_commodity_mnemonic(get_default_currency_guid()) = get_variable('Default currency')
		)
	then
		call write_report(l_report, 'Commodity manipulation routines returned unexpected result.', 'plain');
	end if;

	-- Test account management routines

	-- mark gnucash db status as undefined
	call delete_variable('Gnucash status');

	-- Check gnucash database can be read from	
	select 	count(*)
	into 	l_integer1
	from 	versions
	where	table_name = 'Gnucash';

	if l_integer1 = 1 then 
		call post_variable('Gnucash status', 'R');
	else
		call write_report(l_report, 'Gnucash database could not be written to', 'plain');
	end if;

	-- Check gnucash database can be written to (non fatal error; just stops CustomGnucash RW operations)
	if 	get_variable('Gnucash status') = 'R' then

		set l_text = new_guid();

		insert into versions (table_name, table_version) 
		values 	(l_text, 1);

		select 	count(*)
		into 	l_integer1
		from 	versions
		where 	table_name = l_text;

		if l_integer1 = 1 then
			call put_variable('Gnucash status', 'RW');
			delete from versions where table_name = l_text;
		end if;

	end if;

	-- log results
	
	call post_variable('CustomGnucash status', ifnull(l_report, 'OK'));
	-- call log('CustomGnuCash status = ' || get_variable('CustomGnucash status'));
end;
//

-- Run self-check tests
call customgnucash_status();

call log('CustomGnucash compiled at ' || current_timestamp);


-- MySQL scheduler
-- MySQL users need the EVENT privilege to manage the MySQL event scheduler :
-- For example (as a DBA user) : GRANT EVENT ON gnucash.* TO gnucash;

-- MySQL event scheduler needs to be turned on
-- this will turn on the scheduler for *all* your MySQL databases
-- it needs to be performed by a user with SUPER privileges (a DBA user)
-- You may need to set "event-scheduler = ON" in the [mysqld] section of your /etc/my.cnf file to start the scheduler when mysqld starts
--  SET GLOBAL event_scheduler = ON;
-- //

-- [1] Housekeeping events

-- Event to clean up customgnucash log table (default : keep last 30 days only)
drop event if exists housekeeping;
//
create event housekeeping
on schedule every 1 month starts from_days( to_days( date_add( current_timestamp, interval 1 day ))) -- at midnight
comment 'Keeps customgnucash structure and data up to date.'
do
begin

	-- check system status
	call customgnucash_status();

	if get_variable('CustomGnucash status') =  'OK' then 

		-- check if underlying Gnucash DB has changed and replace stale views if it has
		call create_views();

		-- clean up log table
		delete from log where datediff(current_timestamp, logdate) > get_variable('Keep log');
		-- optimize table log;

		-- clean up variable table
		-- report creation procedures should manage their own history
		-- delete from customgnucash.variable where variable like 'report\_%' and datediff(current_timestamp, logdate) > 365;
		-- optimize table variable;

	end if;
end;
//

-- Event to automatically calculate capital gains
drop event if exists calculate_capital_gains;
//
create event calculate_capital_gains
on schedule every 1 day starts date_add( from_days( to_days( current_timestamp )),  interval 25 hour )  -- at 1AM
comment 'Calculates capital gains and adds them to gnucash.splits table.'
do
begin
	if 	get_variable('CustomGnucash status') = 'OK' then 

		call post_all_gains();

	end if; 
end;
//

-- Event to automatically clean up duplicates in the prices table
-- normally, there are no duplicates inserted by the routines above, but it can happen during debugging
-- does not affect duplicates inserted by any other means (via the GnuCash GUI, for example)
drop event if exists clean_prices;
//
create event clean_prices
on schedule every 1 month starts str_to_date(concat(extract(year_month from date_add(current_timestamp, interval 1 month)),'15'), '%Y%m%d')
comment 'Cleans out duplicate values from the gnucash.prices, optimizes said table.'
do
begin
	if 	get_variable('CustomGnucash status') = 'OK' then 

		call clean_prices();

	end if;
end;
//

-- [2] Reporting events
-- these are entirely optional and probably need tweaking for personal use
-- the user also needs to regularly schedule : 
-- call get_reports(1);
-- to extract the created reports to console (where you can email them, or whatever you want to do with them)

-- report buy/sell signals every day (null report if no signal)
drop event if exists alert_target_allocations;
//
create event alert_target_allocations
on schedule every 1 day starts date_add( from_days( to_days( current_timestamp )),  interval 27 hour ) -- at 3AM
comment 'Reports buy/sell signals on selected stock.'
do
begin
	if 	get_variable('CustomGnucash status') =  'OK' then 

		call report_target_allocations( get_account_guid(get_variable('Stocks ISA account')), 'alert');
		call report_target_allocations( get_account_guid(get_variable('SIPP')), 'alert');

	end if;
end;
//

-- report remaining ISA allowance on the first day of each month
-- only useful to UK users
drop event if exists report_remaining_isa_allowance;
//
create event report_remaining_isa_allowance
on schedule every 1 month starts str_to_date(concat(extract(year_month from date_add(current_timestamp, interval 1 month)),'01'), '%Y%m%d')
comment 'Reports how much remains to be used in your UK ISA allowance.'
do
begin
	if 	get_variable('CustomGnucash status') =  'OK' 
		and get_variable('Jurisdiction') =  'UK'
	then 

		call report_remaining_isa_allowance(null);

	end if;
end;
//

-- report target allocations on the second day of each month
drop event if exists report_target_allocations;
//
create event report_target_allocations
on schedule every 1 month starts str_to_date(concat(extract(year_month from date_add(current_timestamp, interval 1 month)),'02'), '%Y%m%d')
comment 'Reports actual vs target asset allocation.'
do
begin
	if 	get_variable('CustomGnucash status') =  'OK' then 

		call report_target_allocations( get_account_guid(get_variable('Stocks ISA account')), 'report');
		call report_target_allocations( get_account_guid(get_variable('SIPP')), 'report');

	end if;
end;
//

-- report asset allocations on the third day of each month
drop event if exists report_asset_allocations;
//
create event report_asset_allocations
on schedule every 1 month starts str_to_date(concat(extract(year_month from date_add(current_timestamp, interval 1 month)),'03'), '%Y%m%d')
comment 'Reports asset allocation by class and location'
do
begin
	if 	get_variable('CustomGnucash status') =  'OK' then 

		call report_asset_allocation( get_account_guid('Assets'), 'Asset class', current_timestamp );
		call report_asset_allocation( get_account_guid('Assets'), 'Location', current_timestamp );

	end if;
end;
//

-- report gains and losses on the fourth day of each month
drop event if exists report_asset_allocations;
//
create event report_asset_allocations
on schedule every 1 month starts str_to_date(concat(extract(year_month from date_add(current_timestamp, interval 1 month)),'04'), '%Y%m%d')
comment 'Reports asset allocation by class and location'
do
begin
	if 	get_variable('CustomGnucash status') =  'OK' then 

		call report_account_gains( null, null, null );

	end if;
end;
//

call log('CustomGnucash schedules set at ' || current_timestamp);
