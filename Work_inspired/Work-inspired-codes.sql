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