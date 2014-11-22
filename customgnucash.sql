/*
GnuCash MySql routines
Author : Adam Harrington
Date : 22 November 2014
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

-- A non-GnuCash database should be used 
-- we want to minimise interference with default GnuCash behaviour or upgrade paths
use customgnucash;

-- database flags
-- set sql_mode=ansi;
set sql_mode=PIPES_AS_CONCAT;

delimiter //


-- [A.1] Logging table
create table if not exists log (
	id			int 		not null 	auto_increment,
	logdate		timestamp 	default 	current_timestamp,
	log			text 		character set utf8,
	primary key (id)
);
//

-- Adds a line to the log table (used mainly for debugging)
drop procedure if exists log;
//
create procedure log
	(
		p_value		text
	)
begin
	insert into log (log)
	values (p_value);
end;
//

-- [A.2] User-defined global variables
-- drop table if exists variable;
-- //
create table if not exists variable (
	variable 	varchar(700) not null,
	value		text character set utf8,
	primary key	(variable)
);
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
	deterministic
begin
	declare l_value text;
	
	if variable_exists(p_variable) then

		select distinct value
		into l_value
		from variable
		where variable = p_variable;

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
		insert into variable (variable, value)
		values (p_variable, p_value);
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
		update variable
		set value = p_value
		where variable = p_variable;
	end if;
end;
//

-- Required global variables (stored in custom table "variable"
call post_variable ('Default currency', 'GBP');
//
call post_variable ('Tax year end', '6 April');
//
call post_variable ('Account separator', ':');
//
call post_variable ('Default timezone', 'Europe/London');
//

-- GnuCash accounts used in ISA allowance calculations
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

-- GnuCash accounts used in gains calculations
call post_variable ('Interest account', 'Income:Interest');
//
call post_variable ('Dividends account', 'Income:Dividend Income');
//
call post_variable ('Capital gains account', 'Income:Capital gains');
//

-- GnuCash accounts used in tax calculations
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
call post_variable ('Inheritance tax nil rate band 2014', '325000'); 
//
call post_variable ('Inheritance tax rate 2014', '0.4'); 
//
call post_variable ('Inheritance tax nil rate band 2015', '325000'); 
//
call post_variable ('Inheritance tax rate 2015', '0.4'); 
//

-- [A.3] MySQL doesnt-support-arrays workaround
-- this workaround uses CSV strings instead

-- gets a +ve or -ve numbered element from a CSV list 
-- ie get_element('A,B,C,D', -2, ',') = 'C'
drop function if exists get_element;
//
create function get_element
	(
		p_array		varchar(60000),
		p_index		tinyint,
		p_separator	varchar(5)
	)
	returns varchar(1000)
	no sql
begin
	declare l_len tinyint;
	declare l_count tinyint;

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
		in		p_element	varchar(1000),
		in		p_separator	char(1)
	)
	no sql
begin
	set p_separator = ifnull(p_separator, ',');
	if p_element is not null then
		set p_array = trim( p_separator from concat( ifnull(p_array, '' ), p_separator, p_element) );
	end if;
end;
//

-- [A.4] Miscellaneous standalone routines

-- converts a number into an html 'bar' (used for emailing simple graphical results)
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
				'<table border=0 cellpadding=0 cellspacing=0 bgcolor=', ifnull(p_colour,'black'), '><tr>',
				repeat('<td>&nbsp;</td>', round(p_value,0)),
				'</tr></table>'
			);
end;
//

-- returns new random guid for use when inserting rows into GnuCash tables
-- I don't know what algorithm GnuCash actually uses to generate these
-- I'm hoping a 1/16^32 chanbce of accidental repetition is adequate 
-- (about once every 1^31 years, if the routine is used once a second and MySQL rand() is perfectly random - which it isnt)
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
		if now() > str_to_date( concat( get_variable('Tax year end'), extract(year from now())), '%d %M %Y') then
			-- then tax year end is next calendar year
			return str_to_date( concat( get_variable('Tax year end'), extract(year from (now() + interval ( ifnull(p_index,0) + 1) year )), '00:00:00'), '%d %M %Y %H:%i:%s');
		else
			return str_to_date( concat( get_variable('Tax year end'), extract(year from (now() + interval ifnull(p_index,0) year )), '00:00:00'), '%d %M %Y %H:%i:%s');
		end if;

	else
		return null;
	end if;
end;
//

-- writes a new line to a given variable (for creating long text reports)
drop procedure if exists write_variable;
//
create procedure write_variable
	(
		inout	p_report	text,
		in		p_line		varchar(2048)
	)
	no sql
begin
	if p_report is null then
		set p_report = ifnull(p_line,'');
	else
		if locate('<html>', p_report) > 0 then
			set p_report = concat( p_report, ifnull(p_line,'') );
		else
			set p_report = concat( p_report, '\n', ifnull(p_line,'') );
		end if;
	end if;
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
begin
	declare l_count tinyint;

	select 	count(commodities.guid)
	into 	l_count
	from 	gnucash.commodities commodities
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
		p_guid varchar(32)
	)
	returns varchar(2048)
	deterministic
begin
	declare l_namespace varchar(2048);

	select distinct	commodities.namespace 
	into 	l_namespace 
	from 	gnucash.commodities commodities
	where 	commodities.guid = p_guid
	limit 	1;

	return trim(l_namespace);
end;
//

-- [R] returns true if specified commodity namespace is 'CURRENCY'
-- note that commodity indices such as XAU (gold) is also considere a currency (by GnuCash, not by me!)
drop function if exists is_currency;
//
create function is_currency
	(
		p_guid varchar(32)
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
		p_mnemonic varchar(2048)
	)
	returns varchar(32)
	deterministic
begin
	declare l_guid varchar(32);

	select distinct	commodities.guid 
	into 	l_guid 
	from 	gnucash.commodities commodities
	where 	upper(commodities.mnemonic) = upper(p_mnemonic) 
	limit 	1;

	return trim(l_guid);
end;
//

-- [R] returns mnemonic ('GBP', 'IUKD.L) for given commodity guid
drop function if exists get_commodity_mnemonic;
//
create function get_commodity_mnemonic
	(
		p_guid varchar(32)
	)
	returns varchar(2048)
begin
	declare l_mnemonic varchar(2048);

	select distinct	commodities.mnemonic 
	into 	l_mnemonic 
	from 	gnucash.commodities commodities
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
	from 	gnucash.commodities commodities
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

	select distinct	prices.currency_guid 
	into 	l_guid
	from 	gnucash.prices prices
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
		p_guid			varchar(32),
		p_date			timestamp
	)
	returns decimal (15,5)
begin
	declare l_value decimal (15,5);

	-- set default date
	set p_date = ifnull(p_date, now());

	select	price
	into 	l_value
	from
		(
		select 	distinct round(prices.value_num/prices.value_denom, 5) as price,
				prices.date as date
		from 	gnucash.prices prices
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
				gnucash.splits splits
			join gnucash.accounts accounts on splits.account_guid = accounts.guid
			join gnucash.transactions transactions on splits.tx_guid = transactions.guid
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
-- this function intentionally ignores (ransaction) commodity values in the splits table (unlike get_commodity_value)
-- because at the moment it is only used to update price quotes
drop function if exists get_commodity_latest_date;
//
create function get_commodity_latest_date
	(
		p_guid			varchar(32)
	)
	returns timestamp
begin
	declare l_date timestamp;

	select distinct date
	into 	l_date
	from 	gnucash.prices prices
	where 	prices.commodity_guid = p_guid
	order by prices.date desc
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
	returns bigint(20)
begin
	declare l_denom bigint(20);

	select 	value_denom
	into 	l_denom
	from 	gnucash.prices prices
	where 	prices.commodity_guid = p_guid
	order by prices.date desc
	limit 	1;

	-- if that didn't work, use the commodities table (which defines fractional currency units)
	if l_denom is null and is_currency(p_guid) then
		select 	fraction
		into 	l_denom
		from 	gnucash.commodities
		where 	guid = p_guid
		limit 	1;
	end if;

	-- you could also use the splits table if all else fails (unimplemented)

	return l_denom;
end;
//

-- [R] converts a value from one currency/commodity unit to another, using the latest exchange rate valid on a given date
-- relies entirely on exchange rates in the GnuCash database, so won't work as a general FX calculator
drop function if exists convert_value;
//
create function convert_value
	(
		p_value	decimal(20,6),
		p_from	varchar(32),
		p_to	varchar(32),
		p_date	timestamp
	)
	returns decimal (20,6)
begin
	declare l_primary_conversion decimal(20,6);
	declare l_primary_currency varchar(32);
	declare l_secondary_conversion decimal(20,6);
	declare l_secondary_currency varchar(32);

	-- return null or 0 if value is null or zero
	if ifnull(p_value, 0) = 0 
	then
		return p_value;
	end if;

	-- assume p_from and p_to are GBP if null
	set p_from = ifnull(p_from, get_commodity_guid( get_variable('Default currency') ));
	set p_to = ifnull(p_to, get_commodity_guid( get_variable('Default currency') ));
	
	-- short circuit where p_from = p_to (or both were null)
	if p_from = p_to 
	then
		return p_value;
	end if;

	-- assume date is "now" if null
	set p_date = ifnull(p_date, now());

	-- get the p_from->primary_currency conversion rate (which may not be in p_to units; its in whatever p_from is quoted in)
	set l_primary_conversion = get_commodity_value(p_from, p_date);
	set l_primary_currency = get_commodity_currency(p_from);

	-- if you have a good conversion rate and p_from is quoted in p_to units, we are finished (example : USD->GBP, IUKD.L->GBP, PHPM.L->USD)
	if 	l_primary_conversion is not null 
		and l_primary_currency is not null 
		and p_to = l_primary_currency then

		return round(p_value * l_primary_conversion, 6);

	end if;

	-- perhaps we couldnt find a primary conversion rate because only X->GBP is quoted and GBP->X is being requested 
	-- eg USD->GBP is priced in the DB, but not GBP->USD
	if l_primary_conversion is null then
		
		-- firstly, try looking up the (inversed) rates for p_to->p_from instead (ie, around the wrong way)
		set l_primary_conversion = (1 / get_commodity_value(p_to, p_date));
		set l_primary_currency = get_commodity_currency(p_to);

		-- if we now have a good conversion rate and p_to is quoted in p_from units, we are finished
		if 	l_primary_conversion is not null 
			and l_primary_currency is not null 
			and p_from = l_primary_currency then

			return round(p_value * l_primary_conversion, 6);

		end if;

	end if;

	-- if we have no primary conversion rate, or no primary currency, by this point, then bail
	-- there may be no data to support the conversion

	if l_primary_conversion is not null and l_primary_currency is not null then 

		-- we need a secondary conversion (we have converted into the primary currency, but need a further conversion to p_to)
		-- eg PHPM.L(->USD)->GBP; l_primary_conversion = PHPM.L->USD & l_primary_currency = USD & p_to = GBP, but USD->GBP not known
		-- eg IUKD.L(->GBP)->EUR; l_primary_conversion = IUKD.L->GBP & l_primary_currency = GBP & p_to = EUR, but GBP->EUR not known
		-- eg EUR-(->GBP)->USD; l_primary_conversion = EUR->GBP & l_primary_currency = GBP & p_to = USD, but GBP->USD not known

		-- get the primary_currency->secondary_currency conversion rate (which may not be in p_to units; its in whatever l_primary_currency is quoted in)
		set l_secondary_conversion = get_commodity_value(l_primary_currency, p_date);
		set l_secondary_currency = get_commodity_currency(l_primary_currency);

		-- if we have a good conversion rate and l_primary_currency is quoted in p_to units, we are finished
		-- eg PHPM.L(->USD)->GBP
		if 	l_secondary_conversion is not null 
			and l_secondary_currency is not null 
			and p_to = l_secondary_currency then

			return round(p_value * l_primary_conversion * l_secondary_conversion, 6);

		end if;

		-- perhaps we couldnt find a primary conversion rate because only X->GBP is quoted and GBP->X is being requested 
		-- eg IUKD.L(->GBP)->EUR, EUR-(->GBP)->USD
		if l_secondary_conversion is null then
			
			-- firstly, try looking up the (inversed) rates for secondary_currency->primary_currency instead (ie, around the wrong way)
			set l_secondary_conversion = (1 / get_commodity_value(p_to, p_date));
			set l_secondary_currency = get_commodity_currency(p_to);

			-- if we now have a good conversion rate and p_to is quoted in p_from units, we are finished
			if 	l_secondary_conversion is not null 
				and l_secondary_currency is not null 
				and l_primary_currency = l_secondary_currency then

				return round(p_value * l_primary_conversion * l_secondary_conversion, 6);

			end if;
		end if;
	end if;

	-- if we've got this far, then all is lost!
	return null;
end;
//

-- [B.2] Transaction and split management

-- [R] returns true if there is already a relationship between two specified accounts in a transaction
-- this is irrespective of the 'direction' of the transaction
drop function if exists split_exists;
//
create function split_exists
	(
		p_transaction_guid	varchar(32),
		p_account1			varchar(32),
		p_account2			varchar(32)
	)
	returns boolean
begin
	declare l_count tinyint;
	
	select 		count(transactions.guid)
	into 		l_count
	from		
				gnucash.transactions transactions
		join 	gnucash.splits splits1
			on	transactions.guid = splits1.tx_guid
		join 	gnucash.splits splits2
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
		p_account1			varchar(32),
		p_account2			varchar(32)
	)
	returns boolean
begin
	declare l_count tinyint;

	select		count(transactions.guid)
	into		l_count
	from		
				gnucash.transactions transactions
		join 	gnucash.splits splits1
			on	transactions.guid = splits1.tx_guid
		join 	gnucash.splits splits2
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
	returns decimal(20,6)
begin
	declare l_date 	timestamp;
	declare l_value decimal(20,6) default 0;

	-- short circuit
	-- if not transaction_exists(p_guid1, p_guid2) then
	-- 	return 0;
	-- end if;

	-- set default currency
	set p_currency = ifnull( p_currency, get_commodity_guid( get_variable('Default currency') ) );

	-- set default date
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	gnucash.transactions;
	end if;
	set p_date2 = ifnull(p_date2, now());

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
					gnucash.splits splits2
			join	gnucash.transactions transactions2
				on	transactions2.guid = splits2.tx_guid	
		where
				p_guid2 regexp concat( '[[:<:]]', splits2.account_guid, '[[:>:]]' )
			and	splits2.tx_guid in
			(
				select		transactions1.guid
				from
							gnucash.transactions transactions1
					join 	gnucash.splits splits1
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

-- MySQL doesn't support recursive functions making the processing if parent-child account relationships awkward
-- so instead, I've got an account_map view of the gnucash accounts table which maps parent-child to 10 levels

-- [R] *customgnucash* view of *gnucash* tables to aid in account identification
create or replace view account_map
as
select distinct
	accounts.guid,
	upper( accounts.name ) as short_name,
	upper(
		trim( get_variable('Account separator') from
		replace(
			concat(
				ifnull(p10.name,''), get_variable('Account separator'), 
				ifnull(p9.name,''), get_variable('Account separator'), 
				ifnull(p8.name,''), get_variable('Account separator'), 
				ifnull(p7.name,''), get_variable('Account separator'),
				ifnull(p6.name,''), get_variable('Account separator'),
				ifnull(p5.name,''), get_variable('Account separator'),
				ifnull(p4.name,''), get_variable('Account separator'), 
				ifnull(p3.name,''), get_variable('Account separator'), 
				ifnull(p2.name,''), get_variable('Account separator'), 
				ifnull(p1.name,''), get_variable('Account separator'), 
				accounts.name
			)
		, 'Root Account', '')
		) 
	) as long_name,
	get_element(
		concat(
			ifnull(p10.guid,''), get_variable('Account separator'), 
			ifnull(p9.guid,''), get_variable('Account separator'), 
			ifnull(p8.guid,''), get_variable('Account separator'), 
			ifnull(p7.guid,''), get_variable('Account separator'), 
			ifnull(p6.guid,''), get_variable('Account separator'),
			ifnull(p5.guid,''), get_variable('Account separator'),
			ifnull(p4.guid,''), get_variable('Account separator'), 
			ifnull(p3.guid,''), get_variable('Account separator'), 
			ifnull(p2.guid,''), get_variable('Account separator'), 
			ifnull(p1.guid,''), get_variable('Account separator'), 
			accounts.guid
		), 2, get_variable('Account separator') ) as root_guid
	-- group_concat(distinct children.guid) as direct_children,
	-- count(distinct children.guid) as count_direct_children
	-- get_account_type(accounts.guid) as type,
	-- get_account_value(accounts.guid, null) as amount,
	-- get_commodity_mnemonic(get_account_commodity(accounts.guid)) as commodity,
	-- convert_value(get_account_value(accounts.guid,null),get_account_commodity(accounts.guid),null,null) as value
from
	gnucash.accounts
	left outer join gnucash.accounts p1
		on accounts.parent_guid = p1.guid
	left outer join gnucash.accounts p2
		on p1.parent_guid = p2.guid
	left outer join gnucash.accounts p3
		on p2.parent_guid = p3.guid
	left outer join gnucash.accounts p4
		on p3.parent_guid = p4.guid
	left outer join gnucash.accounts p5
		on p4.parent_guid = p5.guid
	left outer join gnucash.accounts p6
		on p5.parent_guid = p6.guid
	left outer join gnucash.accounts p7
		on p6.parent_guid = p7.guid
	left outer join gnucash.accounts p8
		on p7.parent_guid = p8.guid
	left outer join gnucash.accounts p9
		on p8.parent_guid = p9.guid
	left outer join gnucash.accounts p10
		on p9.parent_guid = p10.guid
	-- left outer join gnucash.accounts children
		-- on accounts.guid = children.parent_guid
where
	get_commodity_mnemonic(get_account_commodity(accounts.guid)) != 'template'
-- group by
	-- 1,2,3,4;
//

-- [R] returns true if given account name can be found in GnuCash
drop function if exists account_exists;
//
create function account_exists
	(
		p_name varchar(2048)
	)
	returns boolean
begin
	declare l_count tinyint;

	set p_name = upper( trim( get_variable('Account separator') from p_name) );

	if locate(get_variable('Account separator'), p_name) = 0 then

		select 	count(guid)
		into 	l_count
		from 	gnucash.accounts accounts
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
		p_guid varchar(32)
	)
	returns boolean
	deterministic
begin
	declare l_placeholder tinyint;

	select distinct	accounts.placeholder
	into 	l_placeholder 
	from 	gnucash.accounts accounts
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
		p_guid varchar(32)
	)
	returns boolean
begin
	declare l_count tinyint;

	select 	count(*)
	into 	l_count
	from 	gnucash.splits
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
		p_guid varchar(32)
	)
	returns boolean
	deterministic
begin
	declare l_hidden tinyint;

	select distinct	accounts.hidden
	into 	l_hidden 
	from 	gnucash.accounts accounts
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
	from 	gnucash.accounts accounts
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
	from	gnucash.accounts accounts
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
		from 	gnucash.accounts accounts
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
	from 	gnucash.accounts accounts
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
	from 	gnucash.accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	return trim(l_guid);
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
	from 	gnucash.accounts accounts
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
		from 	gnucash.accounts accounts
			left outer join gnucash.accounts children
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
	declare l_all_parents 	varchar(2048);
	declare l_parent 		varchar(32);
	declare l_child			varchar(32);

	set p_recursive = ifnull(p_recursive, false);

	-- direct parent (singular) only
	select distinct	accounts.parent_guid 
	into 	l_parent
	from 	gnucash.accounts accounts
	where 	accounts.guid = p_guid 
	limit 	1;

	call put_element(l_all_parents, l_parent, ',');
	set l_child = l_parent;

	-- if recursive has been selected, then look further ...
	if p_recursive then

		while is_child(l_child) do

			select distinct	accounts.parent_guid 
			into 	l_parent
			from 	gnucash.accounts accounts
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
		p_recursive		boolean
	)
	returns boolean
	deterministic
begin
	declare l_parent_guid	varchar(32);

	-- do simple check first
	select parent_guid
	into l_parent_guid
	from gnucash.accounts accounts
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
	declare l_accounts			varchar(2048);
	declare l_counter			tinyint default 1;

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
				gnucash.accounts accounts
			join 	gnucash.slots slots on accounts.guid = slots.obj_guid and slots.name = 'notes'
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
	declare l_date 				timestamp;

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
		from 	gnucash.transactions;
	end if;
	set p_date2 = ifnull(p_date2, now());

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- if we are adding up children accts also, standardise on default currency
	if p_children = true and p_currency is null then
		set p_currency = get_commodity_guid( get_variable('Default currency') );
	else
		-- otherwise just use whatever the account uses (which might be share units) if no currency specified
		set p_currency = ifnull(p_currency, get_account_commodity(p_guid) );
	end if;

	-- if no children account rollup is required (or possible), do a simple sum
	if p_children = false or is_parent(p_guid) is false then

		select		sum(splits.quantity_num/splits.quantity_denom)
		into 		l_acct_value
		from 		gnucash.splits splits
			join 	gnucash.transactions transactions 
				on 	splits.tx_guid = transactions.guid
		where 		splits.account_guid = p_guid
			and	 	transactions.post_date >= p_date1
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
			from 		gnucash.splits splits
				join 	gnucash.transactions transactions 
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
			from 		gnucash.splits splits
				join 	gnucash.transactions transactions 
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

-- [R] Calculates three "costs" of an account
-- for use in calculating unrealised gains, or as a denominator in %age gain calcs 
-- v slow and probably inefficient!
drop procedure if exists get_costs;
//
create procedure get_costs
	(
		in p_guid				varchar(32),
		in p_date1				timestamp,
		in p_date2				timestamp,

		out	p_remainder_cost	decimal(20,6), -- STOCK/ASSET : the original cost of what has *not* been sold (for use in calculating unrealised gains)
		out	p_sold_cost			decimal(20,6), -- STOCK/ASSET : the original cost of what *has* been sold (for use in calculating %age realised gains)
		out	p_average_cost		decimal(20,6)  -- BANK/CASH/STOCK/ASSET : the average cost of an account, at times of dividend or interest payments 
	)
procedure_block : begin

	declare l_stock_split_ratio			decimal(20,6);
	declare	l_expense					decimal(20,6);
	declare l_date						timestamp;
	declare l_previous_transaction_guid	varchar(32);

	-- variables for holding transaction cursor output
	declare l_transaction_guid 			varchar(32);
	declare	l_post_date					timestamp;
	declare l_action					varchar(32);
	declare	l_class						varchar(32);
	declare l_quantity 					decimal(20,6);
	declare l_value 					decimal(20,6);
	declare l_transactions_done 		boolean default false;
	declare l_transactions_done_temp 	boolean default false;

	-- variables for holding  tally cursor output
	declare l_tally_transaction_guid_bought	varchar(32);
	declare l_tally_quantity_bought 		decimal(20,6);
	declare l_tally_quantity_sold 			decimal(20,6);
	declare l_tally_done 					boolean default false;
	declare l_tally_done_temp				boolean default false;

	-- outer block cursors
	declare lc_transaction cursor for
		select distinct
			transactions.guid,
			transactions.post_date,
			upper(splits.action),
			case
				when splits.account_guid = p_guid 																		then "3.SELF"
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Dividends account')), true) 		then "2.DIVIDEND"
				-- when is_child_of(splits.account_guid, get_account_guid( get_variable('Capital gains account')), true) 	then "2.CAPITAL GAIN"
				when is_child_of(splits.account_guid, get_account_guid( get_variable('Interest account')), true) 		then "2.INTEREST"
				else concat('1.', get_account_type(splits.account_guid))
			end as class,
			splits.quantity_num / splits.quantity_denom,
			convert_value(
				splits.value_num / splits.value_denom,
				transactions.currency_guid,
				get_commodity_guid( get_variable('Default currency')),
				transactions.post_date
			)
		from
			gnucash.transactions
			join gnucash.splits 
				on transactions.guid = splits.tx_guid
					and transactions.guid in 
						(	select 	splits.tx_guid 
							from 	gnucash.splits 
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

	-- call log('START get_costs');

	-- temp table to keep a running tally of what's actually in the stock/asset account
	drop temporary table if exists stock_tally;
	create temporary table stock_tally (
		id						smallint not null auto_increment,
		transaction_guid_bought	varchar(32),
		post_date_bought		timestamp default 0,
		quantity_bought			mediumint,
		unit_value_bought		decimal(20,6),
		quantity_sold			mediumint,
		primary key (id)
	);

	-- temp table to keep track of accuont costs at times of dividend and interest payments
	drop temporary table if exists cost_tally;
	create temporary table cost_tally (
		account_cost			decimal(20,6)
	);

	-- set defaults
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	gnucash.transactions;
	end if;
	set p_date2 = ifnull(p_date2, now());

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- set output parms to 0
	set p_remainder_cost	= 0;
	set	p_sold_cost			= 0;
	set	p_average_cost		= 0;

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
			if l_class regexp "EXPENSE"	then 
				set l_expense = ifnull(l_expense,0) + l_value;
			end if;

			-- calculate cost of account whenever there is a dividend payment
			if l_class regexp "DIVIDEND" 
				and l_post_date >= p_date1
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
						set 	quantity_bought 	= quantity_bought 		* l_stock_split_ratio,
								quantity_sold 		= quantity_sold 		* l_stock_split_ratio,
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

	if get_account_type(p_guid) in ('STOCK', 'ASSET') then

		-- calculate original cost of whatever's left in the account
		select 	ifnull( sum( (quantity_bought - quantity_sold) * unit_value_bought ), 0)
		into 	p_remainder_cost
		from 	stock_tally;

		-- calculate original cost of whatever's sold from the account
		select 	ifnull( sum( quantity_sold * unit_value_bought ), 0)
		into 	p_sold_cost
		from 	stock_tally;

	end if;

	-- calculate average cost (at times of dividend or interest payments) over period
	-- this is not likely to be a 100% accurate method of getting % returns on dividends or interest payments
	select 	ifnull(avg(account_cost), 0)
	into 	p_average_cost
	from 	cost_tally
	where 	account_cost > 0;

	-- debugging only
	-- select * from stock_tally order by id;

	-- call log('END get_costs');

end; -- outer block
//

-- [C.1] Reports

-- [R] Returns a table itemising capital gains, dividends and interest returns 
-- in default currency, as absolute %, as % pa
-- may take a v long time if you have many accounts to process
drop procedure if exists get_gains;
//
create procedure get_gains 
	(
		in	p_guid		varchar(32),
		in 	p_date1		timestamp,
		in 	p_date2		timestamp
	)
procedure_block : begin
	declare	l_guid						varchar(32);
	declare l_asset_account_done 		boolean default false;
	declare l_asset_account_done_temp 	boolean default false;
	declare	l_remainder_cost			decimal(20,6);
	declare	l_sold_cost					decimal(20,6);
	declare	l_average_cost				decimal(20,6);
	declare l_date						timestamp;
	declare	l_earliest_transaction_date	timestamp;
	declare l_latest_transaction_date	timestamp;
	declare	l_v_earliest_transaction_date	timestamp;
	declare l_v_latest_transaction_date		timestamp;
	declare	l_years						decimal(20,6);
	declare	l_account_name				varchar(2048);
	declare l_capital_gains 			decimal(20,6);
	declare	l_account_value 			decimal(20,6);
	declare	l_dividends					decimal(20,6);
	declare	l_interest					decimal(20,6);

	-- I cant calculate capital gains on mutual funds or property as I dont know their unit value
	declare lc_asset_account cursor for
		select distinct guid
		from account_map
		where
			root_guid = get_account_guid('ASSETS')
			and (guid = p_guid or p_guid is null)
			and get_account_type(guid) in ('ASSET', 'STOCK', 'BANK')
			and not is_placeholder(guid)
			and is_used(guid)
			and get_account_attribute(guid, 'ASSET CLASS') not in ('MUTUAL FUND', 'PROPERTY');
	declare continue handler for not found set l_asset_account_done =  true;
	
	-- call log('START get_gains');

	-- set defaults
	if p_date1 is null then
		select 	min(post_date)
		into 	p_date1
		from 	gnucash.transactions;
	end if;
	set p_date2 = ifnull(p_date2, now());

	-- make sure dates are in the right order
	if p_date2 < p_date1 then
		set l_date = p_date2;
		set p_date2 = p_date1;
		set p_date1 = l_date;
	end if;

	-- temp tables to hold resulting data
	drop temporary table if exists report;
	create temporary table report (
		account				varchar(2048),
		realised_gains 		decimal(20,6),
		unrealised_gains	decimal(20,6),
		dividends			decimal(20,6),
		interest			decimal(20,6),
		remainder_cost		decimal(20,6),
		sold_cost			decimal(20,6),
		average_cost		decimal(20,6),
		years				decimal(20,6)
	);

	-- have to mirror results because of MySQL error 1137 when using same temp table more than once (!!!)
	drop temporary table if exists summary_report;
	create temporary table summary_report (
		account				varchar(2048),
		realised_gains 		decimal(20,6),
		unrealised_gains	decimal(20,6),
		dividends			decimal(20,6),
		interest			decimal(20,6),
		remainder_cost		decimal(20,6),
		sold_cost			decimal(20,6),
		average_cost		decimal(20,6)
	);

	open lc_asset_account;	
	set l_asset_account_done = false;
	
	asset_account_loop : loop
		
		fetch lc_asset_account into l_guid;
	
		if l_asset_account_done then 
			-- call log('LEAVE asset_account_loop');
			leave asset_account_loop;
		else
			set l_asset_account_done_temp = l_asset_account_done;
		end if;

		-- check p_date1 is not earlier than earliest transaction in account 
		select 	max(dates.date)
		into 	l_earliest_transaction_date
		from
		(
			select  min(post_date) as date
			from 	gnucash.transactions
				join gnucash.splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = l_guid
			union
			select 	p_date1
		) dates;

		-- check p_date2 is not later than latest transaction in account 
		select 	min(dates.date)
		into 	l_latest_transaction_date
		from
		(
			select  max(post_date) as date
		
			from 	gnucash.transactions
				join gnucash.splits
					on transactions.guid = splits.tx_guid
			where	splits.account_guid = l_guid
			having	min(post_date) != max(post_date)
			union
			select 	p_date2
		) dates;

		-- keep a track of the absolutely earliest and latest transaction date for all accounts being reported
		if l_earliest_transaction_date < l_v_earliest_transaction_date or l_v_earliest_transaction_date is  null
		then
			set l_v_earliest_transaction_date = l_earliest_transaction_date;
		end if;

		if l_latest_transaction_date > l_v_latest_transaction_date or l_v_latest_transaction_date is  null
		then
			set l_v_latest_transaction_date = l_latest_transaction_date;
		end if;

		-- get specialised cost values		
		call get_costs(l_guid, l_date, p_date2, l_remainder_cost, l_sold_cost, l_average_cost);

		set l_account_name = get_account_long_name(l_guid);

		-- add values to report table
		if get_account_type(l_guid) in ('STOCK', 'ASSET') then

			set l_capital_gains = get_transactions_value(l_guid, get_account_guid( 	get_variable('Capital gains account')),	null, l_earliest_transaction_date, l_latest_transaction_date, true);
			set l_account_value = get_account_value(l_guid, get_commodity_guid( get_variable('Default currency')), 			null, l_latest_transaction_date, false);
			set l_dividends = get_transactions_value(l_guid, get_account_guid( 	get_variable('Dividends account')), 		null, l_earliest_transaction_date, l_latest_transaction_date, true);

			-- add results to temp table
			insert into report
			(
				account,
				realised_gains,
				unrealised_gains,
				dividends,
				interest,
				remainder_cost,
				sold_cost,
				average_cost,
				years
			)
			values
			(
				l_account_name,
				l_capital_gains,
				l_account_value - l_remainder_cost,
				l_dividends,
				null,
				l_remainder_cost,
				l_sold_cost,
				l_average_cost,
				timestampdiff(DAY, l_earliest_transaction_date, l_latest_transaction_date) / 365
			);

			insert into summary_report
			(
				account,
				realised_gains,
				unrealised_gains,
				dividends,
				interest,
				remainder_cost,
				sold_cost,
				average_cost
			)
			values
			(
				l_account_name,
				l_capital_gains,
				l_account_value - l_remainder_cost,
				l_dividends,
				null,
				l_remainder_cost,
				l_sold_cost,
				l_average_cost
			);

		elseif get_account_type(l_guid) in ('CASH', 'BANK') then

			set l_interest = get_transactions_value(	l_guid, get_account_guid( get_variable('Interest account')), null, l_earliest_transaction_date, l_latest_transaction_date, true);

			-- add results to temp table
			insert into report
			(
				account,
				realised_gains,
				unrealised_gains,
				dividends,
				interest,
				remainder_cost,
				sold_cost,
				average_cost,
				years
			)
			values
			(
				get_account_long_name(l_guid),
				null,
				null,
				null,
				l_interest,
				null,
				null,
				l_average_cost,
				timestampdiff(DAY, l_earliest_transaction_date, l_latest_transaction_date) / 365
			);

			insert into summary_report
			(
				account,
				realised_gains,
				unrealised_gains,
				dividends,
				interest,
				remainder_cost,
				sold_cost,
				average_cost
			)
			values
			(
				get_account_long_name(l_guid),
				null,
				null,
				null,
				l_interest,
				null,
				null,
				l_average_cost
			);

		end if;

		set l_asset_account_done = l_asset_account_done_temp;

	end loop;

	close lc_asset_account;	

	-- print report
	select
		replace(replace(account, 'ASSETS:', ''), ':', '<br>')		as "Account",

		ifnull(round(realised_gains,2), '&nbsp;')		as "Realised gains",
		if( ifnull( realised_gains,0 ) = 0 or ifnull( sold_cost,0 ) = 0, 
			'&nbsp;', 
			round( (realised_gains * 100) / (sold_cost), 2)
			) 									as "Realised gains (% absolute)", 
		if( ifnull( realised_gains,0 ) = 0 or ifnull( sold_cost,0) = 0, 
			'&nbsp;', 
			round( (realised_gains * 100) / (sold_cost * years ), 2)
			) 									as "Realised gains (% annualised)", 

		ifnull(round(unrealised_gains,2), '&nbsp;')	as "Unrealised gains",
		if( ifnull( unrealised_gains,0 ) = 0 or ifnull( remainder_cost,0 ) = 0, 
			'&nbsp;', 
			round( (unrealised_gains * 100) / (remainder_cost), 2)
			) 									as "Unrealised gains (% absolute)", 
		if( ifnull( unrealised_gains,0 ) = 0 or ifnull( remainder_cost,0 ) = 0, 
			'&nbsp;', 
			round( (unrealised_gains * 100) / (remainder_cost * years ), 2)
			) 									as "Unrealised gains (% annualised)", 

		ifnull(round(dividends,2), '&nbsp;')			as "Dividends",
		if( ifnull( dividends,0 ) = 0 or ifnull( average_cost,0 ) = 0, 
			'&nbsp;', 
			round( (dividends * 100) / (average_cost), 2)
			) 									as "Dividends (% absolute)", 
		if( ifnull( dividends,0 ) = 0 or ifnull( average_cost,0 ) = 0, 
			'&nbsp;', 
			round( (dividends * 100) / (average_cost * years ), 2)
			) 									as "Dividends (% annualised)", 

		ifnull( round(interest,2), '&nbsp;')			as "Interest",
		if( ifnull( interest,0 ) = 0 or ifnull( average_cost,0 ) = 0, 
			'&nbsp;', 
			round( (interest * 100) / (average_cost ), 2)
			) 									as "Interest (% absolute)",
		if( ifnull( interest,0 ) = 0 or ifnull( average_cost,0 ) = 0, 
			'&nbsp;', 
			round( (interest * 100) / (average_cost * years ), 2)
			) 									as "Interest (% annualised)"
		
		-- debugging values
		/*,
		sold_cost,
		remainder_cost,
		average_cost,
		years
		*/

	from report
	where
		ifnull(realised_gains,0) != 0
		or ifnull(unrealised_gains,0) != 0
		or ifnull(dividends,0) != 0
		or ifnull(interest,0) != 0
	
	union

	select
		' TOTAL',
		ifnull( convert( sum( round(realised_gains,2)), char), '&nbsp;'),
		if( ifnull( sum(realised_gains),0 ) = 0 or ifnull( sum(sold_cost),0 ) = 0, 
			'&nbsp;', 
			round( ( sum(realised_gains) * 100) / sum(sold_cost), 2)
		),
		if( ifnull( sum(realised_gains),0 ) = 0 or ifnull( sum(sold_cost),0) = 0, 
			'&nbsp;',
			round( ( sum(realised_gains) * 100) / ( sum(sold_cost) * timestampdiff(DAY, l_v_earliest_transaction_date, l_v_latest_transaction_date) / 365) , 2)
		), 

		ifnull( convert( sum(round(unrealised_gains,2)), char), '&nbsp;'),
		if( ifnull( sum(unrealised_gains),0 ) = 0 or ifnull( sum(remainder_cost),0 ) = 0, 
			'&nbsp;', 
			round( ( sum(unrealised_gains) * 100) / sum(remainder_cost), 2)
		),
		if( ifnull( sum(unrealised_gains),0 ) = 0 or ifnull( sum(remainder_cost),0) = 0, 
			'&nbsp;', 
			round( ( sum(unrealised_gains) * 100) / ( sum(remainder_cost) * timestampdiff(DAY, l_v_earliest_transaction_date, l_v_latest_transaction_date) / 365) , 2)
		), 

		ifnull( convert( sum(round(dividends,2)), char), '&nbsp;'),
		if( ifnull( sum(dividends),0 ) = 0 or ifnull( sum(average_cost),0 ) = 0, 
			'&nbsp;', 
			round( (sum(dividends) * 100) / sum(average_cost), 2)
		),
		if( ifnull( sum(dividends),0 ) = 0 or ifnull( sum(average_cost),0 ) = 0, 
			'&nbsp;', 
			round( (sum(dividends) * 100) / ( sum(average_cost) * timestampdiff(DAY, l_v_earliest_transaction_date, l_v_latest_transaction_date) / 365) , 2)
		),

		ifnull( convert( sum(round(interest,2)), char), '&nbsp;'),
		if( ifnull( sum(interest),0 ) = 0 or ifnull( sum(average_cost),0 ) = 0, 
			'&nbsp;', 
			round( ( sum(interest) * 100) / sum(average_cost), 2)
		),
		if( ifnull( sum(interest),0 ) = 0 or ifnull( sum(average_cost),0 ) = 0, 
			'&nbsp;', 
			round( ( sum(interest) * 100) / ( sum(average_cost) * timestampdiff(DAY, l_v_earliest_transaction_date, l_v_latest_transaction_date) / 365) , 2)
		) 

	from summary_report
	where
		ifnull(realised_gains,0) != 0
		or ifnull(unrealised_gains,0) != 0
		or ifnull(dividends,0) != 0
		or ifnull(interest,0) != 0

	order by 1;

	-- call log('END get_gains');
end;
//

-- [R] returns how much remains in your ISA allowance this tax year (only)
-- only applicable in the UK
drop function if exists get_remaining_isa_allowance;
//
create function get_remaining_isa_allowance()
	returns decimal(20,6)
begin
	declare l_isa_contribution decimal(20,6) default 0;
	declare l_cash_accounts varchar(65000);
	declare l_ISA_accounts varchar(2048);
	declare l_tax_year_start timestamp;
	declare l_tax_year_end timestamp;
	declare l_cash_account_counter smallint default 1;
	declare l_ISA_account_counter smallint default 1;

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

			set l_isa_contribution = l_isa_contribution +
									get_transactions_value(
										get_element( l_ISA_accounts, l_ISA_account_counter, ',' ),
										get_element( l_cash_accounts, l_cash_account_counter, ',' ),
										null,
										l_tax_year_start,
										l_tax_year_end
									);

			set l_cash_account_counter = l_cash_account_counter + 1;

		end while;

		set l_ISA_account_counter = l_ISA_account_counter + 1;

	end while;

	return round( get_variable( concat('ISA allowance ', date_format(l_tax_year_end, '%Y') ) ) - l_isa_contribution , 2);
end;
//

-- [R] Breaks down allocation of given account by asset class or location
-- relies entirely on user-defined account attributes such as [asset class=<asset class>], [location=<location>]
drop procedure if exists get_allocation;
//
create procedure get_allocation
	(
		p_guid		varchar(32),
		p_variable	varchar(2048),
		p_date		timestamp
	)
procedure_block : begin
	declare l_total decimal(20,6);

	set p_guid = ifnull(p_guid, get_account_guid('Assets'));
	set p_variable = ifnull(p_variable, 'TYPE');
	set p_date = ifnull(p_date, now());
	set l_total = get_account_value( p_guid, null, null, p_date, true);

	select
		ifnull(
			case upper(p_variable)
				when 'TYPE' 		then get_account_type(account_map.guid)
				when 'ASSET CLASS' 	then
					ifnull(
							get_account_attribute(account_map.guid,'Asset class'), 
							if( get_account_type(account_map.guid) = 'BANK', 'CASH', get_account_type(account_map.guid))
						)
				else
					get_account_attribute(account_map.guid, p_variable)
			end,
			'UNKNOWN'
		)
		as classification,
		round(
			sum(
				get_account_value(
					account_map.guid, 
					get_commodity_guid( get_variable( 'Default currency') ), 
					null,
					p_date, 
					false)
			)
		,2) as GBP,
		round(
			(
			sum(
				get_account_value(
					account_map.guid, 
					get_commodity_guid( get_variable( 'Default currency') ), 
					null, 
					p_date, 
					false)
			) * 100) / l_total
		,2) as '%',
		html_bar(
				round(
						(
						sum(
							get_account_value(
								account_map.guid, 
								get_commodity_guid( get_variable( 'Default currency') ), 
								null, 
								p_date, 
								false)
						) 
						* 100) / l_total
					,0) 
			,
			case
				when 
					round(
							(
							sum(
								get_account_value(
									account_map.guid, 
									get_commodity_guid( get_variable( 'Default currency') ), 
									null, 
									p_date, 
									false)
							) 
							* 100) / l_total
						,0) > 80 
				then 'red'
				when
					round(
							(
							sum(
								get_account_value(
									account_map.guid, 
									get_commodity_guid( get_variable( 'Default currency') ), 
									null, 
									p_date, 
									false)
							) 
							* 100) / l_total
						,0) > 50 
				then 'orange'
				when
					round(
							(
							sum(
								get_account_value(
									account_map.guid, 
									get_commodity_guid( get_variable( 'Default currency') ), 
									null, 
									p_date, 
									false)
							) 
							* 100) / l_total
						,0) > 20 
				then 'blue'
				else 'green'
			end
			) as '% (as a graph)'
	from
		account_map
	where
		root_guid = p_guid
		and not is_placeholder(account_map.guid)
	group by
		1
	having sum(	
				get_account_value(
					account_map.guid, 
					get_commodity_guid( get_variable( 'Default currency') ), 
					null, 
					p_date, 
					false)
			) != 0

	union
	
	select
		'TOTAL',
		round(l_total,2),
		100.00,
		html_bar(100,'gray')

	order by
		3 desc;
end;
//

-- [R] calculates *UK* capital gains, income and inheritance tax for specified year (default latest completed tax year)
-- all amounts in GBP
-- based on UK HMRC rules July 2014
-- only applies to persons aged under 65 (there's a whole raft of other rules for them!)
-- incomplete
drop procedure if exists get_uk_tax_report;
//
create procedure get_uk_tax_report
	(
		p_index	tinyint
	)
procedure_block : begin
	declare l_report_name 				varchar(700);
	declare l_report 					text;
	declare l_tax_year_start 			timestamp;
	declare l_tax_year_end 				timestamp;

	declare l_taxable_taxed_salary 		decimal(20,6);
	declare l_taxable_untaxed_salary 	decimal(20,6);
	declare l_taxable_taxed_interest 	decimal(20,6);
	declare l_taxable_untaxed_interest	decimal(20,6);
	declare l_taxable_dividends 		decimal(20,6);
	declare l_taxable_capital_gains 	decimal(20,6);
	declare l_inheritance 				decimal(20,6);
	declare l_gross_income 				decimal(20,6);
	declare l_gross_salary 				decimal(20,6);
	declare l_gross_savings 			decimal(20,6);
	declare l_total_tax_paid 			decimal(20,6);

	declare l_interest_income_tax_paid 	decimal(20,6);
	declare l_dividends_income_tax_paid	decimal(20,6);
	declare l_salary_income_tax_paid 	decimal(20,6);
	-- declare l_national_insurance_paid decimal(20,6);
	declare l_capital_gains_tax_paid 	decimal(20,6);
	declare l_tax_rebates 				decimal(20,6);
	declare l_self_assessment_tax_paid 	decimal(20,6);
	declare l_inheritance_tax_paid 		decimal(20,6);
	declare l_personal_allowance 		decimal(20,6);

	declare l_income_tax_calculated 		decimal(20,6) default 0;
	-- declare l_national_insurance_calculated decimal(20,6) default 0;
	declare l_capital_gains_tax_calculated 	decimal(20,6) default 0;
	declare l_inheritance_tax_calculated 	decimal(20,6) default 0;

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
	set l_gross_savings = l_taxable_taxed_interest + l_taxable_untaxed_interest;
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
	call write_variable(l_report, null);
	call write_variable(l_report, 'Tax report');
	call write_variable(l_report, repeat('-', length(l_report_name)) );

	call write_variable(l_report, concat(	'Income tax to pay :\t\t\t\t', 
											get_variable('Default currency'), 
											' ',
											ifnull(l_income_tax_calculated, 'ERROR')
									)
						);
	call write_variable(l_report, concat(	'National insurance to pay :\t\t\t', 
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

-- [D.1] Database update routines
-- All custom GnuCash routines that *alter* the GnuCash database are listed here
-- If you want *no chance* of these running, then don't allow the customgnucash user write-access to gnucash tables

-- [RW] Adds a new commodity price to the commodity table
-- if its sane, and hasn't already been added
-- designed to be called from an OS scheduler using gnc-fq-dump to obtain quotes :
drop procedure if exists post_commodity_price;
//
create procedure post_commodity_price
	(
		p_symbol	varchar(10),
		p_date		varchar(10),
		p_currency	varchar(5),
		p_last		decimal(20,6),
		p_source	varchar(255)
	)
procedure_block : begin
	declare l_previous_price decimal(20,6);
	declare l_previous_date	timestamp;
	declare l_previous_denom bigint(20);
	declare l_previous_currency varchar(32);

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

			insert into gnucash.prices (
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

		-- else

			-- log action
			-- call log('Did NOT insert new price ' || p_currency || convert(p_last, char) || ' for ' || if( is_currency( get_commodity_guid(trim(p_symbol)) ) , 'currency ', 'commodity ') || trim(p_symbol) );

		end if;
	end if;
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
		p_value				decimal(20,6),
		p_transaction_guid	varchar(32),
		p_date_posted		timestamp,
		p_description		varchar(2048)
	)
procedure_block : begin
	declare l_exists				tinyint default 0;
	declare l_guid					varchar(32);
	declare l_default_currency		varchar(32);
	declare l_value_denom			bigint(20);
	declare l_value_num				bigint(20);
	declare l_quantity_denom_from	bigint(20);
	declare l_quantity_num_from 	bigint(20);
	declare l_quantity_denom_to		bigint(20);
	declare l_quantity_num_to 		bigint(20); 
	
	-- verify inputs are sane [1]
	if 	p_date_posted is null 
		or p_date_posted > now() 
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
	from	gnucash.accounts
	where	guid in (p_account_from, p_account_to);

	if l_exists != 2 then
		call log('Post split aborted. Accounts ' || p_account_from || ' or ' || p_account_to || ' could not be found.');
		leave procedure_block;
	end if;

	if p_transaction_guid is not null then

		set l_exists = 0;

		select 	count(*)
		into 	l_exists
		from	gnucash.transactions
		where	guid = p_transaction_guid;

		if l_exists != 1 then
			leave procedure_block;
		end if;

	end if;

	-- calculate values beforehand so all inserts are as quick as possible
	set l_default_currency = get_commodity_guid( get_variable( 'Default currency'));
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

		insert into gnucash.transactions 
			(guid, currency_guid, post_date, enter_date, description)
		values
			(	p_transaction_guid, 
				l_default_currency, 
				p_date_posted, 
				now(), 
				ifnull(p_description, 'Transaction added by customgnucash.post_split')
			);
		call log('Added transaction ' || p_transaction_guid );

	end if;

	-- always add 2 splits, one for each side of the transaction
	set l_guid = new_guid();
	insert into gnucash.splits
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
	insert into gnucash.splits
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

end;
//

-- [RW] calculates (and adds splits, if required) for realised capital gains for specified account
-- uses HMRC rules regarding capital gains calculations; when shares are indistinguishable, earlier bought shares are sold first
-- does nothing if a (sale) transaction already has a capital gain posted (even if its wrong)
-- only affects accounts of ASSET or STOCK type
-- manages stock splits (consolidations) if splits are added to GnuCash through the splits tool (which flags them with 'Split' in the action field)
-- doesn't manage accounts without a unit price; (like some mutual or pension funds) 
drop procedure if exists post_gain;
//
create procedure post_gain
	(
		p_guid		varchar(32)
	)			
procedure_block : begin
	declare l_realised_gain 			decimal(20,6) default 0;
	declare l_capital_gains_guid		varchar(32);
	declare l_stock_split_ratio			decimal(20,6);

	-- variables for holding stock cursor output
	declare l_transaction_guid 			varchar(32);
	declare l_action					varchar(32);
	declare l_post_date 				timestamp;
	declare l_enter_date 				timestamp;
	declare l_total_quantity 			decimal(20,6);
	declare l_total_value 				decimal(20,6);
	declare l_unit_value 				decimal(20,6);
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
						get_commodity_guid( get_variable('Default currency') ), 
						transactions.post_date 
						) 
					)
				),
			abs(
				sum( 
					convert_value( 
						splits.value_num/splits.value_denom, 
						transactions.currency_guid, 
						get_commodity_guid( get_variable('Default currency') ), 
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
			gnucash.transactions
			join gnucash.splits 
				on transactions.guid = splits.tx_guid
					and splits.tx_guid in (
						select splits.tx_guid 
						from gnucash.splits 
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

	-- calculate gains on STOCK or ASSET account types only
	if get_account_type(p_guid) in ('STOCK', 'ASSET') then

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
							declare l_stock_tally_done_temp	boolean default false;

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
end; -- outer block
//

-- [RW] calculates (and adds) realised capital gains for *all* applicable asset accounts
-- specifically excludes accounts with account attribute [asset class=mutual fund] or [asset class=property] (I can't work gains out for these account types)
-- designed to be called from OS scheduler
drop procedure if exists post_all_gains;
//
create procedure post_all_gains ()
procedure_block : begin
	declare	l_guid						varchar(32);
	declare l_asset_account_done 		boolean default false;
	declare l_asset_account_done_temp 	boolean default false;

	declare lc_asset_account cursor for
		select distinct guid
		from account_map
		where
			root_guid = get_account_guid('ASSETS')
			and get_account_type(guid) in ('ASSET', 'STOCK')
			and not is_placeholder(guid)
			and get_account_attribute(guid, 'ASSET CLASS') not in ('MUTUAL FUND', 'PROPERTY');
	declare continue handler for not found set l_asset_account_done =  true;
	
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
end;
//

call log('CustomGnucash compiled at ' || now());
