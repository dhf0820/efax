require 'efax'
data = File.open('cons.pdf').read

EFax::Request.account_id = '7029223171'
EFax::Request.user = 'dhfren'
EFax::Request.password = 'dhfren'

send_response1 = EFax::OutboundRequest.post('Theresa French', 'VertiSoft Corp', '702-924-0718', 'Test Fax', data, {transmissionid: 5432 })
#send_response = EFax::OutboundRequest.post('Theresa French', 'VertiSoft Corp', '702-503-9665', 'Test Fax', data, {transmissionid: 5432 })
send_response = EFax::OutboundRequest.post('Theresa French', 'VertiSoft Corp', '702-924-0718', 'Test Fax', data, {transmissionid: 5432 })
#send_response = EFax::OutboundRequest.post('Theresa French', 'VertiSoft Corp', '702-924-0718', 'Test Fax', data, 'PDF')
current_status = EFax::OutboundStatus.post(send_response.doc_id)