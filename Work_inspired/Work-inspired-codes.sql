 -- Example of advanced call center analytics: categorizing inbound/outbound calls 
-- linked to support tickets, with multi-level classification and daily deduplication.
-- Fully anonymized from real-world production data.

 WITH call_data AS (
    SELECT
        customer_id,
        DATE_TRUNC('day', call_timestamp) AS call_day,
        call_timestamp,
        direction,                  -- inbound / outbound
        network_provider,
        billed_minutes,
        ivr_handled,
        ivr_choice,
        agent_talk_seconds,
        
        -- Call type classification
        CASE
            WHEN ivr_handled = 1 AND ivr_choice = 'closed' THEN 'IVR_CLOSED'
            WHEN ivr_handled = 1 AND agent_talk_seconds = 0 THEN 'IVR_ONLY'
            WHEN ivr_handled = 1 AND agent_talk_seconds > 0 THEN 'IVR_AND_AGENT'
            ELSE 'DIRECT_AGENT'
        END AS call_type,
        
        -- Cost calculation (generic rates)
        billed_minutes * 
            CASE 
                WHEN network_provider = 'Provider_A' THEN 90
                ELSE 135 
            END AS call_cost,
        
        CASE 
            WHEN billed_minutes > 0 THEN 'ANSWERED'
            ELSE 'UNANSWERED'
        END AS call_outcome,
        
        call_performance_score,
        ticket_subtype,
        
        -- Detailed ticket categorization (business-agnostic)
        CASE
            WHEN ticket_subtype IN ('Overdue', 'Near Lockout') 
                OR ticket_subtype ILIKE '%autodialer%' 
                THEN 'Portfolio Management'
                
            WHEN ticket_subtype ILIKE '%balance%' 
                OR ticket_subtype ILIKE '%enquiry%' 
                OR ticket_subtype ILIKE '%pricing%' 
                OR ticket_subtype ILIKE '%account info%' 
                OR ticket_subtype ILIKE '%insurance%' 
                THEN 'General Enquiry'
                
            WHEN ticket_subtype ILIKE '%battery%' 
                OR ticket_subtype ILIKE '%panel%' 
                OR ticket_subtype ILIKE '%lighting%' 
                OR ticket_subtype ILIKE '%technical%' 
                OR ticket_subtype ILIKE '%problem%' 
                OR ticket_subtype ILIKE '%usb%' 
                OR ticket_subtype ILIKE '%system%' 
                THEN 'Technical Support'
                
            WHEN ticket_subtype ILIKE '%promotion%' 
                OR ticket_subtype ILIKE '%campaign%' 
                OR ticket_subtype ILIKE '%offer%' 
                THEN 'Promotions'
                
            WHEN ticket_subtype ILIKE '%payment%' 
                OR ticket_subtype ILIKE '%unlock%' 
                OR ticket_subtype ILIKE '%token%' 
                OR ticket_subtype ILIKE '%refund%' 
                THEN 'Payments & Codes'
                
            WHEN ticket_subtype ILIKE '%complaint%' 
                OR ticket_subtype ILIKE '%feedback%' 
                THEN 'Customer Feedback'
                
            WHEN ticket_subtype ILIKE '%sales%' 
                OR ticket_subtype ILIKE '%upsell%' 
                OR ticket_subtype ILIKE '%onboarding%' 
                THEN 'Sales Process'
                
            ELSE 'Other'
        END AS ticket_category,
        
        -- Higher-level service classification
        CASE
            WHEN ticket_subtype ILIKE '%technical%' 
                OR ticket_subtype ILIKE '%battery%' 
                OR ticket_subtype ILIKE '%repair%' 
                THEN 'Problem Resolution'
            WHEN ticket_subtype ILIKE '%payment%' 
                OR ticket_subtype ILIKE '%balance%' 
                OR ticket_subtype ILIKE '%enquiry%' 
                OR ticket_category IN ('General Enquiry', 'Promotions', 'Sales Process')
                THEN 'Customer Request'
            WHEN ticket_subtype ILIKE '%incident%' 
                OR ticket_subtype ILIKE '%fraud%' 
                OR ticket_subtype ILIKE '%theft%' 
                THEN 'Incident Handling'
            ELSE 'Miscellaneous'
        END AS service_level,
        
        -- Deduplicate: keep most recent call per customer per day
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, DATE_TRUNC('day', call_timestamp)
            ORDER BY call_timestamp DESC
        ) AS rn
    FROM calls_log cl
    LEFT JOIN call_desk cd 
        ON cd.call_id = cl.call_id
    LEFT JOIN (
        -- Get the primary ticket per call (first ticket if multiple)
        SELECT 
            call_id,
            subtype_name AS ticket_subtype
        FROM (
            SELECT 
                call_id,
                ticket_id,
                ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY ticket_id) AS rn
            FROM call_ticket_link
        ) ranked
        JOIN tickets t ON t.ticket_id = ranked.ticket_id
        WHERE ranked.rn = 1
    ) primary_ticket
        ON primary_ticket.call_id = cd.desk_call_id
    WHERE cl.call_date >= '2026-01-01'
      AND cl.billed_minutes > 0
)

SELECT
    call_day,
    direction,
    call_type,
    call_outcome,
    network_provider,
    call_performance_score,
    ticket_subtype,
    ticket_category,
    service_level,
    COUNT(*) AS total_calls,
    SUM(billed_minutes) AS total_billed_minutes,
    SUM(call_cost) AS total_call_cost
FROM call_data
WHERE rn = 1
  AND ticket_category = 'Other'  -- example filter; adjust or remove as needed
GROUP BY
    call_day,
    direction,
    call_type,
    call_outcome,
    network_provider,
    call_performance_score,
    ticket_subtype,
    ticket_category,
    service_level
ORDER BY call_day
LIMIT 1000;


---SQL CODE FOR CUSTOMER SEGMENTATION


 SELECT
        t.customer_id,
        COUNT(DISTINCT t.primary_id)                                      AS all_time_payment_frequency,
        SUM(t.amount / 100.0)                                             AS all_time_total_paid,
        MAX(t.added_at_utc)                                               AS last_payment_date_all_time,
        EXTRACT(DAY FROM CURRENT_DATE - MAX(t.added_at_utc))               AS recency_days_all_time,
        MAX(t.daily_rate) / 100.0                                          AS current_daily_rate,
        (MAX(t.daily_rate) / 100.0) * 180                                  AS expected_pay_180d,

        -- PVE based on last 6 months only
        CASE
            WHEN MAX(t.daily_rate) = 0 THEN NULL
            ELSE ROUND( (SUM(t.amount)/100.0) / ((MAX(t.daily_rate)/100.0) * 180) * 100 , 2)
        END                                                               AS pve_percent_last_180d,

        -- PVE category (6 months)
        CASE
            WHEN MAX(t.daily_rate) = 0 THEN 'No Rate'
            WHEN SUM(t.amount) / NULLIF((MAX(t.daily_rate)/100.0)*180, 0) >= 100 THEN '100%+ (Super Payer)'
            WHEN SUM(t.amount) / NULLIF((MAX(t.daily_rate)/100.0)*180, 0) >= 90  THEN '90–99% (Excellent)'
            WHEN SUM(t.amount) / NULLIF((MAX(t.daily_rate)/100.0)*180, 0) >= 70  THEN '70–89% (Good)'
            WHEN SUM(t.amount) / NULLIF((MAX(t.daily_rate)/100.0)*180, 0) >= 50  THEN '50–69% (Average)'
            ELSE 'Below 50% (At Risk)'
        END                                                               AS pve_category_180d

    FROM your_database.loan_transactions t  -- REPLACE with your actual transactions table
    WHERE t.country = 'YOUR_COUNTRY_CODE'      -- e.g., 'UG' – replace with your target country
      AND t.transaction_type IN ('Payment', 'OverPayment Reducing', 'Migration Amount')
      AND t.added_at_utc >= CURRENT_DATE - INTERVAL '180 days'
      AND t.customer_id IN (SELECT customer_id FROM active_customers)
    GROUP BY t.customer_id
),

demographics AS (
    SELECT
        cs.customer_id,
        COALESCE(
            EXTRACT(YEAR FROM cs.birthdate)::INTEGER,
            pd.birth_year,
            ps.year_of_birth
        ) AS year_of_birth,
        pd.gender,
        pd.occupation,
        pd.area1,
        pd.area2
    FROM your_sensitive_schema.customers_sensitive cs          -- REPLACE with your sensitive customer table
    LEFT JOIN your_database.customer_details pd                -- REPLACE with your public/customer details table
           ON pd.customer_id = cs.customer_id
    LEFT JOIN your_sensitive_schema.person_sensitive ps        -- REPLACE with any additional sensitive person table
           ON ps.primary_phone = cs.primary_phone_number
    WHERE cs.customer_id LIKE 'your_prefix%'                   -- Same prefix as above
)

-- Final output: ALL active customers + 6-month PVE + demographics
SELECT
    a.customer_id,
    COALESCE(p.all_time_payment_frequency, 0)          AS all_time_payment_frequency,
    COALESCE(p.all_time_total_paid, 0)                 AS all_time_total_paid,
    p.last_payment_date_all_time,
    p.recency_days_all_time,
    COALESCE(p.current_daily_rate, 0)                  AS current_daily_rate,
    COALESCE(p.expected_pay_180d, 0)                   AS expected_pay_last_6m,
    p.pve_percent_last_180d,
    COALESCE(p.pve_category_180d, 'No Payment in 180d') AS pve_category_last_6m,
    
    d.year_of_birth,
    d.gender,
    d.occupation,
    d.area1,
    d.area2
FROM active_customers a
LEFT JOIN payment_metrics p ON p.customer_id = a.customer_id
LEFT JOIN demographics d   ON d.customer_id = a.customer_id
ORDER BY p.pve_percent_last_180d DESC NULLS LAST

