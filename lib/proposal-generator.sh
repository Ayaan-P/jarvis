#!/bin/bash
# Grant proposal generation automation for fundraising-cro
# Usage: ./proposal-generator.sh generate-proposal "RFP_file.txt" "organization_profile.md" "output.md"
# Usage: ./proposal-generator.sh template "education" "template.md"

source "${BASH_SOURCE%/*}/utils.sh"

# Find and load environment variables
ENV_PATHS=(
    "./.env"
    "../Claude-Agentic-Files/.env"
    "/home/ayaan/Projects/Claude-Agentic-Files/.env"
    "$HOME/.env"
)

for env_path in "${ENV_PATHS[@]}"; do
    if [[ -f "$env_path" ]]; then
        source "$env_path"
        break
    fi
done

# Generate proposal template based on RFP type
generate_proposal_template() {
    local rfp_type="$1"
    local output_file="$2"
    
    log_info "Generating proposal template for: $rfp_type"
    
    case "$rfp_type" in
        "education"|"workforce_development")
            cat > "$output_file" << 'EOF'
# Grant Proposal: [PROGRAM NAME]
**Submitted to:** [FUNDER NAME]  
**Submitted by:** [ORGANIZATION NAME]  
**Date:** [DATE]  
**Requested Amount:** $[AMOUNT]

## Executive Summary
[2-3 paragraph summary of the project, impact, and funding request]

## Statement of Need
### Problem Definition
[Describe the specific problem this program will address]

### Target Population
- **Primary Beneficiaries:** [Description]
- **Demographics:** [Age, location, socioeconomic status, etc.]
- **Number Served:** [Projected participants]

### Evidence of Need
[Statistical data, research, community assessment findings]

## Program Description
### Project Overview
[Detailed description of the proposed program/project]

### Goals and Objectives
**Goal 1:** [Primary goal]
- Objective 1.1: [Specific, measurable objective]
- Objective 1.2: [Specific, measurable objective]

**Goal 2:** [Secondary goal]
- Objective 2.1: [Specific, measurable objective]
- Objective 2.2: [Specific, measurable objective]

### Program Activities
1. **Activity 1:** [Description]
   - Timeline: [Timeframe]
   - Participants: [Number/type]
   - Outcomes: [Expected results]

2. **Activity 2:** [Description]
   - Timeline: [Timeframe]
   - Participants: [Number/type]
   - Outcomes: [Expected results]

## Methodology and Approach
[Detailed explanation of how the program will be implemented]

### Evidence-Based Practices
[Research and best practices that inform the approach]

### Innovation Elements
[What makes this program unique or innovative]

## Evaluation Plan
### Evaluation Design
[Description of evaluation methodology]

### Performance Metrics
| Metric | Target | Measurement Method | Timeline |
|--------|---------|-------------------|----------|
| [Metric 1] | [Target] | [Method] | [Timeline] |
| [Metric 2] | [Target] | [Method] | [Timeline] |

### Data Collection
[How data will be collected, stored, and analyzed]

## Organizational Capacity
### Organization Overview
[Brief history, mission, and relevant experience]

### Staff Qualifications
- **Project Director:** [Name and qualifications]
- **Program Manager:** [Name and qualifications]
- **Key Staff:** [Names and roles]

### Organizational Experience
[Relevant past programs and outcomes]

### Partners and Collaborations
[Key partnerships that strengthen the project]

## Budget Narrative
### Total Project Budget: $[TOTAL AMOUNT]

**Personnel (X%):** $[AMOUNT]
- Project Director: $[AMOUNT]
- Program Staff: $[AMOUNT]
- Administrative Support: $[AMOUNT]

**Program Costs (X%):** $[AMOUNT]
- Training Materials: $[AMOUNT]
- Equipment: $[AMOUNT]
- Technology: $[AMOUNT]

**Administrative Costs (X%):** $[AMOUNT]
- Overhead: $[AMOUNT]
- Evaluation: $[AMOUNT]

### Cost-Effectiveness
[Explanation of cost per participant/outcome]

## Sustainability Plan
[How the program will continue beyond the grant period]

### Long-term Funding Strategy
[Plans for securing ongoing support]

### Community Investment
[How community will support program continuation]

## Expected Impact
### Short-term Outcomes (Year 1)
[Immediate results expected]

### Long-term Impact (3-5 years)
[Broader community/field impact]

### Alignment with Funder Priorities
[How this project advances the funder's mission]

## Conclusion
[Strong closing paragraph that reinforces the case for support]

---

## Appendices
- Appendix A: Organization Chart
- Appendix B: Board of Directors List
- Appendix C: Audited Financial Statements
- Appendix D: Letters of Support
- Appendix E: Detailed Budget Spreadsheet

EOF
            ;;
        "technology"|"innovation")
            cat > "$output_file" << 'EOF'
# Technology Innovation Grant Proposal: [PROJECT NAME]

## Executive Summary
[2-3 paragraph summary focusing on innovation and technical solution]

## Technical Problem Statement
### Current Technology Gaps
[Specific technology challenges to address]

### Market Analysis
[Technology landscape and opportunity]

## Proposed Solution
### Technical Approach
[Detailed technical methodology]

### Innovation Elements
[What makes this technically innovative]

### Technology Stack
[Specific technologies and platforms]

## Implementation Plan
### Development Phases
[Phased approach to development]

### Technical Milestones
[Key deliverables and timelines]

## Team and Expertise
### Technical Team
[Developer and technical staff qualifications]

### Advisory Board
[Technical advisors and industry experts]

## Budget and Resources
[Technology-focused budget categories]

## Expected Outcomes
### Technical Deliverables
[Specific technology products/tools]

### User Impact
[How end users benefit from the technology]

EOF
            ;;
        *)
            cat > "$output_file" << 'EOF'
# Grant Proposal Template: [PROJECT TITLE]

## Executive Summary
[Compelling 2-3 paragraph overview]

## Statement of Need
[Problem description and evidence]

## Project Description
[Detailed program/project overview]

## Goals and Objectives
[Specific, measurable outcomes]

## Methodology
[Implementation approach]

## Evaluation
[How success will be measured]

## Organizational Capacity
[Qualifications and experience]

## Budget
[Financial plan and justification]

## Sustainability
[Long-term viability plan]

## Conclusion
[Strong closing argument]

EOF
            ;;
    esac
    
    log_info "Proposal template created: $output_file"
}

# Generate customized proposal using AI assistance
generate_ai_proposal() {
    local rfp_file="$1"
    local org_profile="$2"
    local output_file="$3"
    
    log_info "Generating AI-assisted proposal"
    
    if [[ ! -f "$rfp_file" ]]; then
        log_error "RFP file not found: $rfp_file"
        return 1
    fi
    
    if [[ ! -f "$org_profile" ]]; then
        log_error "Organization profile not found: $org_profile"
        return 1
    fi
    
    # Create proposal outline based on RFP requirements
    cat > "$output_file" << EOF
# Grant Proposal: [TO BE CUSTOMIZED]
**Generated:** $(date)  
**Status:** DRAFT - Requires Review and Customization

## RFP Analysis
**Source:** $rfp_file  
**Organization Profile:** $org_profile

## Key RFP Requirements
[AI Analysis of RFP requirements would go here]

## Proposal Sections

### 1. Executive Summary
[AI-generated summary based on org profile and RFP]

### 2. Statement of Need
[Tailored need statement based on RFP focus area]

### 3. Project Description
[Program design aligned with RFP requirements]

### 4. Methodology
[Evidence-based approach matching RFP criteria]

### 5. Evaluation Plan
[Metrics and assessment strategy]

### 6. Organizational Capacity
[Strengths from organization profile]

### 7. Budget
[Financial plan matching RFP guidelines]

### 8. Sustainability
[Long-term planning]

---

## Next Steps for Completion:
1. Review RFP requirements thoroughly
2. Customize all bracketed sections
3. Add specific data and evidence
4. Review budget calculations
5. Proofread and format
6. Add required attachments
7. Submit before deadline

## Notes:
- This is a DRAFT template requiring significant customization
- All sections need organization-specific content
- Budget numbers need actual calculations
- Compliance with RFP format requirements needed

EOF
    
    log_info "AI-assisted proposal draft created: $output_file"
    log_info "IMPORTANT: This draft requires significant customization and review"
}

# Create letter of inquiry (LOI) template
generate_loi_template() {
    local funder_name="$1"
    local project_focus="$2"
    local output_file="$3"
    
    cat > "$output_file" << EOF
# Letter of Inquiry: [PROJECT TITLE]

**To:** $funder_name  
**From:** [ORGANIZATION NAME]  
**Date:** $(date +"%B %d, %Y")  
**Re:** Letter of Inquiry - $project_focus Program

Dear [PROGRAM OFFICER NAME],

## Introduction
[1-2 sentences introducing your organization and its mission]

## Project Overview
[3-4 sentences describing the proposed project and its goals]

## Alignment with Funder Priorities
[2-3 sentences explaining how this project aligns with the funder's interests]

## Requested Support
We respectfully request $[AMOUNT] over [TIME PERIOD] to support this initiative.

## Expected Impact
[2-3 sentences on anticipated outcomes and beneficiaries]

## Next Steps
We would welcome the opportunity to submit a full proposal and would be happy to provide additional information as needed. Thank you for considering our request.

Sincerely,

[SIGNATURE]  
[NAME]  
[TITLE]  
[ORGANIZATION]  
[CONTACT INFORMATION]

---

## Attachment Checklist:
- [ ] Organization overview (1-2 pages)
- [ ] Project budget summary
- [ ] Board of directors list
- [ ] IRS determination letter
- [ ] Most recent audited financials

EOF
    
    log_info "Letter of Inquiry template created: $output_file"
}

# Main execution
case "${1:-help}" in
    "generate-proposal")
        generate_ai_proposal "$2" "$3" "$4"
        ;;
    "template")
        generate_proposal_template "$2" "${3:-proposal_template.md}"
        ;;
    "loi")
        generate_loi_template "$2" "$3" "${4:-letter_of_inquiry.md}"
        ;;
    "help"|*)
        echo "Usage: $0 {generate-proposal|template|loi|help}"
        echo ""
        echo "Commands:"
        echo "  generate-proposal RFP_file org_profile output_file  - Generate AI-assisted proposal"
        echo "  template rfp_type [output_file]                     - Create proposal template"
        echo "  loi funder_name project_focus [output_file]         - Create letter of inquiry"
        echo ""
        echo "RFP Types: education, workforce_development, technology, innovation"
        echo ""
        echo "Examples:"
        echo "  $0 template education"
        echo "  $0 generate-proposal rfp.txt org_profile.md proposal.md"
        echo "  $0 loi 'Gates Foundation' 'Education Innovation'"
        ;;
esac