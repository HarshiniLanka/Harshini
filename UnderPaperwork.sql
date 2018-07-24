
SELECT DISTINCT
		DIV.Division_Name
	 ,  CASE WHEN  PC.PC_Code IS NULL THEN NULL
		  WHEN  PC.PC_Code = '#N/A' THEN NULL
		  ELSE LEFT(PC.PC_Code, (CHARINDEX('-',PC.PC_Code)-1))
		END AS MarketId
	 ,	basinfo.CTX_ID
	 ,	vbasinfo.Company_name AS Business_Name
	 ,  basinfo.custom_8 AS DriverId	 
	 ,  CASE WHEN CAT.Category = '117294' THEN sp.Name 
			 WHEN CAT.Category = '117600' THEN spen.Name
		ELSE NULL
		END AS DriverName
	 ,  spen.Name AS SPE_Name
	 ,  basinfo.custom_17 AS SPDriverId
	 ,  sp.Name AS SP_Name	 
	 ,  sp.contact_title As SPContractTitle
	 ,  spen.contact_title As SPENContractTitle
	 ,  CASE WHEN cd.custom_money_1 = 0 THEN 1 ELSE 0 END AS IsHelper
	 ,  CASE WHEN cd.custom_money_2 = 0 THEN 1 ELSE 0 END AS IsOwner
	 ,  CASE WHEN cd.custom_money_3 = 0 THEN 1 ELSE 0 END AS IsDriver
	 ,  CAT.Category
	 ,  CAT.ContractCategory
	 ,  CONVERT(VARCHAR(11),basinfo.version_date,101) AS Origination_Date
	 ,  INP.inp_date AS InProcess_Date
	 ,	CASE WHEN CAT.Category = '117294' THEN CONVERT(VARCHAR(11),basinfo.effective_date,101)
			 WHEN CAT.Category = '117600' THEN 
									CASE WHEN SPP.sp_pend_date IS NOT NULL THEN SPP.sp_pend_date 
										  ELSE CASE WHEN Cond.spe_cond_date IS NOT NULL THEN Cond.spe_cond_date 
													ELSE CONVERT(VARCHAR(11),basinfo.effective_date,101) 
													END 
										  END 
		END AS OnContract_Date	 
	 ,  CONVERT(VARCHAR(11),basinfo.expriation_date,101) AS OffContract_Date
	 ,  CASE WHEN CHARINDEX('-',ST.ContractStatus) = 0 THEN ST.ContractStatus ELSE SUBSTRING(ST.ContractStatus,CHARINDEX('-',ST.ContractStatus) + 2,50) END AS ContractStatus
	 ,  DATEPART(m,basinfo.effective_date) AS clx_month
	 ,  DATEPART(yy,basinfo.effective_date) AS clx_year

	 ,  CASE WHEN basinfo.expriation_date IS NULL OR CONVERT(VARCHAR(11),basinfo.expriation_date,101) > GETDATE() THEN 1 ELSE 0 END AS IsActive
	 ,  CASE WHEN ST.ContractStatus like '%SPE In Process%' 
				Or ST.ContractStatus like '%Pending SP Activation%' 
				Or ST.ContractStatus like '%In Process%' 
				Or ST.ContractStatus like '%Pending CMS Enroll%' THEN 1 ELSE 0 END AS IsUnderPaperWork
	 ,  CASE WHEN CONVERT(VARCHAR(11),basinfo.expriation_date,101) IS NOT NULL AND CONVERT(VARCHAR(11),basinfo.expriation_date,101) <= GETDATE() THEN 1 ELSE 0 END AS IsDriverTerminated
	 ,  CASE WHEN CONVERT(VARCHAR(11),basinfo.expriation_date,101) IS NULL THEN NULL 
			 WHEN CONVERT(VARCHAR(11),basinfo.expriation_date,101) <= GETDATE() THEN DATEDIFF(dd, CONVERT(VARCHAR(11),basinfo.expriation_date,101), GetDate()) END AS DwellDaysDriverTerminated
	 ,  CASE WHEN CONVERT(VARCHAR(11),basinfo.expriation_date,101) IS NOT NULL 
					AND CONVERT(VARCHAR(11),basinfo.expriation_date,101) <= GETDATE()
					AND  DATEDIFF(dd, CONVERT(VARCHAR(11),basinfo.expriation_date,101), GetDate()) <=21  THEN 1 -- If Driver got Terminated in Last 21 Days consider as TurnedOver
			 ELSE 0 END AS IsDriverTurnedOver
	 --,  ST.ContractStatus
--Into #ContractStatus
FROM		
	CTX_BASIC_INFO basinfo WITH (NOLOCK)
JOIN
	v_CTX_BASIC_INFO vbasinfo WITH (NOLOCK) ON basinfo.CTX_ID = vbasinfo.CTX_ID
LEFT JOIN	
	ctx_custom cd WITH (NOLOCK) ON basinfo.ctx_id = cd.ctx_id

-- Markets or Profit Center
LEFT JOIN	
	(
 		 SELECT	DISTINCT 
			cl.Code AS PC_CODE, 
			cl.custom_1 AS Company, 
			cl.Description AS Market, 
			cl.lookup_Code AS PC_KEY
		 FROM code_lookup cl WITH (NOLOCK)
		 WHERE	
			cl.lookup_name = 'XPO Markets' 
	) PC ON basinfo.custom_6 = PC.PC_KEY 

LEFT JOIN
	(
		 SELECT
			ex.ctx_id,
			LTRIM(RTRIM(Coalesce(ex.first_name,''))) + ' ' + LTRIM(RTRIM(Coalesce(ex.middle_name,''))) + ' ' + LTRIM(RTRIM(Coalesce(ex.last_name,''))) AS Name,
			ex.contact_title,
			ex.facility_name AS Business_Name
		 FROM v_ctx_contacts_external ex WITH (NOLOCK)
		 WHERE --ctx_Id = '53091'
			ex.contact_title LIKE '%Owner%'
	) sp ON basinfo.ctx_id = sp.ctx_id
LEFT JOIN
	(
		 SELECT
			ex.ctx_id,
			LTRIM(RTRIM(Coalesce(ex.first_name,''))) + ' ' + LTRIM(RTRIM(Coalesce(ex.middle_name,''))) + ' ' + LTRIM(RTRIM(Coalesce(ex.last_name,''))) AS Name,
			ex.contact_title,
			ex.facility_name AS Business_Name
		 FROM v_ctx_contacts_external ex WITH (NOLOCK)
		 WHERE 
			ex.contact_title LIKE 'Driver%' OR ex.contact_title LIKE 'Helper%' OR ex.contact_title LIKE 'Employee%'
	) spen ON basinfo.ctx_id = spen.ctx_id
LEFT JOIN	
	(
		 SELECT	DISTINCT 
			cl.code, 
			cl.Lookup_Code AS division, 
			cl.description AS Division_Name 
		 FROM code_lookup cl WITH (NOLOCK)
		 WHERE	
			cl.lookup_name = 'contract division'
	) DIV ON basinfo.dvision = DIV.division
LEFT JOIN	
	(
		 SELECT	DISTINCT 
			cl.Lookup_Code AS Category, 
			cl.description AS ContractCategory
		 FROM	Code_lookup cl WITH (NOLOCK)
		 WHERE	
			cl.lookup_name = 'contract category'
	) CAT ON basinfo.category = CAT.Category
LEFT JOIN
	(
		 SELECT	
			sa.ctx_id,
			CONVERT(VARCHAR(11),MAX(sa.start_time),101) AS inp_date
		 FROM dbo.sys_StatusAudit sa WITH (NOLOCK)
		 WHERE 
			sa.status IN (118446,118598)  -- In-Process 118446- SP , 118598-SPE
		 GROUP BY
			sa.ctx_id
	) INP ON INP.ctx_id = basinfo.ctx_id

-- This Left Join is only for SPE 
LEFT JOIN
	(
		 SELECT	
			sa.ctx_id,
			CONVERT(VARCHAR(11),MAX(sa.start_time),101) AS sp_pend_date
		 FROM dbo.sys_StatusAudit sa WITH (NOLOCK)
		 WHERE 
			sa.status IN (119271,119657)  -- SP Pending Act
		 GROUP BY
			sa.ctx_id
	) SPP ON SPP.ctx_id = basinfo.ctx_id

-- This Left Join is only for SPE 
LEFT JOIN
	(
		 SELECT	
			sa.ctx_id,
			CONVERT(VARCHAR(11),MAX(sa.start_time),101) AS spe_cond_date
		 FROM dbo.sys_StatusAudit sa WITH (NOLOCK)
		 WHERE 
			sa.status IN (118601)  -- SPE Conditional
		 GROUP BY
			sa.ctx_id
	) Cond ON Cond.ctx_id = basinfo.ctx_id

LEFT JOIN	
	(
		 SELECT	DISTINCT 
			cl.code, 
			cl.Lookup_Code AS Status, 
			cl.description AS ContractStatus 
		 FROM code_lookup cl WITH (NOLOCK)
		 WHERE	
			cl.lookup_name = 'contract status'
	) ST ON basinfo.status = ST.Status

WHERE 1=1
--AND basinfo.ctx_Id in ('461','5091')
AND PC.PC_Code IS NOT NULL
AND PC.PC_Code <> '#N/A'
AND CAT.Category IN ('117294', '117600') -- ONLY 117294-SP & 117600- SPES respectively
---AND INP.inp_date IS NOT NULL
AND ST.ContractStatus Not in ('SPE Incomplete') -- Need to check with sachin on Incomplete Drivers (The Category says SPE and the Contract Title is BusinessOwner)
--AND ST.ContractStatus NOT IN ('In Process', 'SPE In Process')-- Need to check with sachin on In Process Drivers if i need to include in this scorecard
AND (ST.Status NOT IN (114502,118447,118445)  -- CANCEL,DECLINED
		OR ST.Status NOT IN (118599,118600)
	)
-- Make Sure only Drivers that are in Contract and the On-Contract Date is not null
AND CASE WHEN CAT.Category = '117294' THEN CONVERT(VARCHAR(11),basinfo.effective_date,101)
			 WHEN CAT.Category = '117600' THEN 
									CASE WHEN SPP.sp_pend_date IS NOT NULL THEN SPP.sp_pend_date 
										  ELSE CASE WHEN Cond.spe_cond_date IS NOT NULL THEN Cond.spe_cond_date 
													ELSE CONVERT(VARCHAR(11),basinfo.effective_date,101) 
													END 
										  END 
		END IS NOT NULL
--AND basinfo.custom_8 ='CE43102'