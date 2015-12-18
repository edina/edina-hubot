// Description:
//   Have Gort responde to Klatu Barada Nikto
//
// Dependencies:
//   None
//
// Configuration:
//   None
//
// Commands:
//   hubot: Klaatu Barada Nikto - Returns URL to wikipedia page.

module.exports = function(robot) {
  robot.respond(/Klaatu Barada Nikto/i, function(res) {
    res.reply('https://en.wikipedia.org/wiki/Klaatu_barada_nikto');
  });
};


